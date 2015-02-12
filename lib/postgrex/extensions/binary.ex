defmodule Postgrex.Extensions.Binary do
  @moduledoc false

  alias Postgrex.TypeInfo
  import Postgrex.BinaryUtils
  require Decimal
  use Bitwise, only_operators: true

  @behaviour Postgrex.Extension

  @numeric_base 10_000
  @default_flag 0x02 ||| 0x04

  @senders ~w(boolsend bpcharsend textsend citextsend varcharsend byteasend
              int2send int4send int8send float4send float8send numeric_send
              uuid_send unknownsend)

  def init(opts),
    do: opts

  def matching(_),
    do: [type: "record"] ++ unquote(Enum.map(@senders, &{:send, &1}))

  def format(_),
    do: :binary

  ### ENCODING ###

  def encode(%TypeInfo{send: "boolsend"}, true, _, _),
    do: <<1>>
  def encode(%TypeInfo{send: "boolsend"}, false, _, _),
    do: <<0>>
  def encode(%TypeInfo{send: "bpcharsend"}, bin, _, _) when is_binary(bin),
    do: bin
  def encode(%TypeInfo{send: "textsend"}, bin, _, _) when is_binary(bin),
    do: bin
  def encode(%TypeInfo{send: "citextsend"}, bin, _, _) when is_binary(bin),
    do: bin
  def encode(%TypeInfo{send: "varcharsend"}, bin, _, _) when is_binary(bin),
    do: bin
  def encode(%TypeInfo{send: "byteasend"}, bin, _, _) when is_binary(bin),
    do: bin
  def encode(%TypeInfo{send: "unknownsend"}, bin, _, _) when is_binary(bin),
    do: bin
  def encode(%TypeInfo{send: "int2send"}, n, _, _) when is_integer(n),
    do: <<n :: int16>>
  def encode(%TypeInfo{send: "int4send"}, n, _, _) when is_integer(n),
    do: <<n :: int32>>
  def encode(%TypeInfo{send: "int8send"}, n, _, _) when is_integer(n),
    do: <<n :: int64>>
  def encode(%TypeInfo{send: "float4send"}, :NaN, _, _),
    do: <<127, 192, 0, 0>>
  def encode(%TypeInfo{send: "float4send"}, :inf, _, _),
    do: <<127, 128, 0, 0>>
  def encode(%TypeInfo{send: "float4send"}, :"-inf", _, _),
    do: <<255, 128, 0, 0>>
  def encode(%TypeInfo{send: "float4send"}, n, _, _) when is_number(n),
    do: <<n :: float32>>
  def encode(%TypeInfo{send: "float8send"}, :NaN, _, _),
    do: <<127, 248, 0, 0, 0, 0, 0, 0>>
  def encode(%TypeInfo{send: "float8send"}, :inf, _, _),
    do: <<127, 240, 0, 0, 0, 0, 0, 0>>
  def encode(%TypeInfo{send: "float8send"}, :"-inf", _, _),
    do: <<255, 240, 0, 0, 0, 0, 0, 0>>
  def encode(%TypeInfo{send: "float8send"}, n, _, _) when is_number(n),
    do: <<n :: float64>>
  def encode(%TypeInfo{send: "numeric_send"}, n, _, _),
    do: encode_numeric(n)
  def encode(%TypeInfo{send: "uuid_send"}, <<_ :: binary(16)>> = bin, _, _),
    do: bin
  def encode(%TypeInfo{send: "array_send", array_elem: elem_oid}, list, types, _) when is_list(list),
    do: encode_array(list, elem_oid, types)
  def encode(%TypeInfo{send: "record_send", comp_elems: elem_oids}, tuple, types, _) when is_tuple(tuple),
    do: encode_record(tuple, elem_oids, types)
  def encode(%TypeInfo{send: "range_send", type: type}, tuple, _, _),
    do: encode_range(type, tuple)

  defp encode_numeric(dec) do
    if Decimal.nan?(dec) do
      <<0 :: int16, 0 :: int16, 0xC000 :: uint16, 0 :: int16>>
    else
      string = Decimal.to_string(dec, :normal) |> :binary.bin_to_list

      if List.first(string) == ?- do
        [_|string] = string
        sign = 0x4000
      else
        sign = 0x0000
      end

      {int, float} = Enum.split_while(string, &(&1 != ?.))
      {weight, int_digits} = Enum.reverse(int) |> encode_numeric_int(0, [])

      if float != [] do
        [_|float] = float
        scale = length(float)
        float_digits = encode_numeric_float(float, [])
      else
        scale = 0
        float_digits = []
      end

      digits = int_digits ++ float_digits
      bin = for digit <- digits, into: "", do: <<digit :: uint16>>
      ndigits = div(byte_size(bin), 2)

      [<<ndigits :: int16, weight :: int16, sign :: uint16, scale :: int16>>, bin]
    end
  end

  defp encode_numeric_float([], [digit|acc]) do
    [pad_float(digit)|acc]
    |> trim_zeros
    |> Enum.reverse
  end

  defp encode_numeric_float(list, acc) do
    {list, rest} = Enum.split(list, 4)
    digit = List.to_integer(list)

    encode_numeric_float(rest, [digit|acc])
  end

  defp encode_numeric_int([], weight, acc) do
    {weight, acc}
  end

  defp encode_numeric_int(list, weight, acc) do
    {list, rest} = Enum.split(list, 4)
    digit = Enum.reverse(list) |> List.to_integer

    if rest != [], do: weight = weight + 1

    encode_numeric_int(rest, weight, [digit|acc])
  end

  defp trim_zeros([0|tail]), do: trim_zeros(tail)
  defp trim_zeros(list), do: list

  defp pad_float(0) do
    0
  end

  defp pad_float(num) do
    num10 = num*10
    if num10 >= @numeric_base do
      num
    else
      pad_float(num10)
    end
  end

  defp encode_array(list, elem_oid, types) do
    encoder = &Postgrex.Types.encode(elem_oid, &1, types)

    {data, ndims, lengths} = encode_array(list, 0, [], encoder)
    lengths = for len <- Enum.reverse(lengths), do: <<len :: int32, 1 :: int32>>
    [<<ndims :: int32, 0 :: int32, elem_oid :: int32>>, lengths, data]
  end

  defp encode_array([], ndims, lengths, _encoder) do
    {"", ndims, lengths}
  end

  defp encode_array([head|tail]=list, ndims, lengths, encoder)
      when is_list(head) do
    lengths = [length(list)|lengths]
    {data, ndims, lengths} = encode_array(head, ndims, lengths, encoder)
    [dimlength|_] = lengths

    rest = Enum.reduce(tail, [], fn sublist, acc ->
      {data, _, [len|_]} = encode_array(sublist, ndims, lengths, encoder)
      if len != dimlength do
        raise ArgumentError, message: "nested lists must have lists with matching lengths"
      end
      [acc|data]
    end)

    {[data|rest], ndims+1, lengths}
  end

  defp encode_array(list, ndims, lengths, encoder) do
    {data, length} = Enum.map_reduce(list, 0, fn elem, length ->
      data = encoder.(elem)
      {data, length + 1}
    end)
    {data, ndims+1, [length|lengths]}
  end

  defp encode_record(tuple, elem_oids, types) do
    list = Tuple.to_list(tuple)
    zipped = :lists.zip(list, elem_oids)

    {data, count} = Enum.map_reduce(zipped, 0, fn {value, oid}, count ->
      data = Postgrex.Types.encode(oid, value, types)
      {[<<oid :: int32>>, data], count + 1}
    end)

    [<<count :: int32>>, data]
  end

  # TODO: Encode ranges generically with typbasetype
  defp encode_range("int4range", tuple) do
    encode_range(tuple, &(<<&1 :: int32>>))
  end

  defp encode_range("int8range", tuple) do
    encode_range(tuple, &(<<&1 :: int64>>))
  end

  defp encode_range("numrange", tuple) do
    encode_range(tuple, fn(bound) ->
      [meta, bin] = encode_numeric(bound)
      meta <> bin
    end)
  end

  defp encode_range(tuple, fun) when is_function(fun) do
    flag = range_flag(tuple)

    case tuple do
      {:"-inf", upper} ->
        flag <> encode_bound(upper, fun)
      {lower, :inf} ->
        flag <> encode_bound(lower, fun)
      {lower, upper} ->
        flag <> encode_bound(lower, fun) <> encode_bound(upper, fun)
    end
  end

  defp encode_bound(value, fun) do
    bin = apply(fun, [value])
    <<byte_size(bin) :: int32>> <> bin
  end

  defp range_flag({:"-inf", _upper}) do
    <<@default_flag ||| 0x08>> # Set lower bound infinity flag
  end

  defp range_flag({_lower, :inf}) do
    <<@default_flag ||| 0x10>> # Set upper bound infinity flag
  end

  defp range_flag({_lower, _upper}) do
    <<@default_flag>> # Inclusive lower and upper bounds
  end

  ### DECODING ###

  def decode(%TypeInfo{send: "boolsend"}, <<1 :: int8>>, _, _),
    do: true
  def decode(%TypeInfo{send: "boolsend"}, <<0 :: int8>>, _, _),
    do: false
  def decode(%TypeInfo{send: "bpcharsend"}, bin, _, _),
    do: bin
  def decode(%TypeInfo{send: "textsend"}, bin, _, _),
    do: bin
  def decode(%TypeInfo{send: "citextsend"}, bin, _, _),
    do: bin
  def decode(%TypeInfo{send: "varcharsend"}, bin, _, _),
    do: bin
  def decode(%TypeInfo{send: "byteasend"}, bin, _, _),
    do: bin
  def decode(%TypeInfo{send: "unknownsend"}, bin, _, _),
    do: bin
  def decode(%TypeInfo{send: "int2send"}, <<n :: int16>>, _, _),
    do: n
  def decode(%TypeInfo{send: "int4send"}, <<n :: int32>>, _, _),
    do: n
  def decode(%TypeInfo{send: "int8send"}, <<n :: int64>>, _, _),
    do: n
  def decode(%TypeInfo{send: "float4send"}, <<127, 192, 0, 0>>, _, _),
    do: :NaN
  def decode(%TypeInfo{send: "float4send"}, <<127, 128, 0, 0>>, _, _),
    do: :inf
  def decode(%TypeInfo{send: "float4send"}, <<255, 128, 0, 0>>, _, _),
    do: :"-inf"
  def decode(%TypeInfo{send: "float4send"}, <<n :: float32>>, _, _),
    do: n
  def decode(%TypeInfo{send: "float8send"}, <<127, 248, 0, 0, 0, 0, 0, 0>>, _, _),
    do: :NaN
  def decode(%TypeInfo{send: "float8send"}, <<127, 240, 0, 0, 0, 0, 0, 0>>, _, _),
    do: :inf
  def decode(%TypeInfo{send: "float8send"}, <<255, 240, 0, 0, 0, 0, 0, 0>>, _, _),
    do: :"-inf"
  def decode(%TypeInfo{send: "float8send"}, <<n :: float64>>, _, _),
    do: n
  def decode(%TypeInfo{send: "numeric_send"}, bin, _, _),
    do: decode_numeric(bin)
  def decode(%TypeInfo{send: "uuid_send"}, bin, _, _),
    do: bin
  def decode(%TypeInfo{send: "array_send"}, bin, types, _),
    do: decode_array(bin, types)
  def decode(%TypeInfo{send: "record_send"}, bin, types, _),
    do: decode_record(bin, types)
  def decode(%TypeInfo{send: "range_send", type: type}, <<flags, payload :: binary>>, _, _),
    do: decode_range(type, flags, payload)

  defp decode_numeric(<<ndigits :: int16, weight :: int16, sign :: uint16, scale :: int16, tail :: binary>>) do
    decode_numeric(ndigits, weight, sign, scale, tail)
  end

  defp decode_numeric(0, _weight, 0xC000, _scale, "") do
    Decimal.new(1, :qNaN, 0)
  end

  defp decode_numeric(_num_digits, weight, sign, scale, bin) do
    {value, weight} = decode_numeric_int(bin, weight, 0)

    case sign do
      0x0000 -> sign = 1
      0x4000 -> sign = -1
    end

    {coef, exp} = scale(value, (weight+1)*4, -scale)
    Decimal.new(sign, coef, exp)
  end

  defp scale(coef, exp, scale) when scale == exp,
    do: {coef, exp}

  defp scale(coef, exp, scale) when scale > exp,
    do: scale(div(coef, 10), exp+1, scale)

  defp scale(coef, exp, scale) when scale < exp,
    do: scale(coef * 10, exp-1, scale)

  defp decode_numeric_int("", weight, acc), do: {acc, weight}

  defp decode_numeric_int(<<digit :: int16, tail :: binary>>, weight, acc) do
    acc = (acc * @numeric_base) + digit
    decode_numeric_int(tail, weight - 1, acc)
  end

  defp decode_array(<<ndims :: int32, _has_null :: int32, oid :: int32, rest :: binary>>,
                    types) do
    {dims, rest} = :erlang.split_binary(rest, ndims * 2 * 4)
    lengths = for <<len :: int32, _lbound :: int32 <- dims>>, do: len
    decoder = &Postgrex.Types.decode(oid, &1, types)

    {array, ""} = decode_array(rest, lengths, decoder)
    array
  end

  defp decode_array("", [], _decoder) do
    {[], ""}
  end

  defp decode_array(rest, [len], decoder) do
    array_elements(rest, len, [], decoder)
  end

  defp decode_array(rest, [len|lens], decoder) do
    Enum.map_reduce(1..len, rest, fn _, rest ->
      decode_array(rest, lens, decoder)
    end)
  end

  defp array_elements(rest, 0, acc, _decoder) do
    {Enum.reverse(acc), rest}
  end

  defp array_elements(<<-1 :: int32, rest :: binary>>, count, acc, decoder) do
    array_elements(rest, count-1, [nil|acc], decoder)
  end

  defp array_elements(<<length :: int32, elem :: binary(length), rest :: binary>>,
                       count, acc, decoder) do
    value = decoder.(<<length :: int32, elem :: binary(length)>>)
    array_elements(rest, count-1, [value|acc], decoder)
  end

  defp decode_record(<<num :: int32, rest :: binary>>, types) do
    decoder = &Postgrex.Types.decode(&1, &2, types)
    record_elements(num, rest, decoder) |> List.to_tuple
  end

  defp record_elements(0, <<>>, _decoder) do
    []
  end

  defp record_elements(num, <<_oid :: int32, -1 :: int32, rest :: binary>>, decoder) do
    [nil | record_elements(num-1, rest, decoder)]
  end

  defp record_elements(num, <<oid :: int32, length :: int32, elem :: binary(length), rest :: binary>>,
                       decoder) do
    value = decoder.(oid, <<length :: int32, elem :: binary(length)>>)
    [value | record_elements(num-1, rest, decoder)]
  end

  # TODO: Decode ranges generically with typbasetype
  defp decode_range("numrange", _flags, <<len :: int32, lower_bound :: binary(len), len2 :: int32, upper_bound :: binary(len2)>>) do
    {decode_numeric(lower_bound), decode_numeric(upper_bound)}
  end

  defp decode_range("numrange", flags, <<len :: int32, single_value :: binary(len)>>) do
    case check_infinite(flags) do
      :lower ->
        {:"-inf", decode_numeric(single_value)}
      :upper ->
        {decode_numeric(single_value), :inf}
    end
  end

  defp decode_range("int4range", _flags, <<_ :: int32, lower_bound :: int32, _ :: int32, upper_bound :: int32>>) do
    {lower_bound, upper_bound - 1}
  end

  defp decode_range("int4range", flags, <<_ :: int32, single_value :: int32>>) do
    case check_infinite(flags) do
      :lower ->
        {:"-inf", single_value - 1}
      :upper ->
        {single_value, :inf}
    end
  end

  defp decode_range("int8range", _flags, <<_ :: int32, lower_bound :: int64, _ :: int32, upper_bound :: int64>>) do
     {lower_bound, upper_bound - 1}
  end

  defp decode_range("int8range", flags, <<_ :: int32, single_value :: int64>>) do
    case check_infinite(flags) do
      :lower ->
        {:"-inf", single_value - 1}
      :upper ->
        {single_value, :inf}
    end
  end

  defp check_infinite(flags) do
    cond do
      (flags &&& 0x8)  != 0 ->
        :lower
      (flags &&& 0x10) != 0 ->
        :upper
    end
  end
end
