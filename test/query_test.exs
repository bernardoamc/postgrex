defmodule QueryTest do
  use ExUnit.Case, async: true
  import Postgrex.TestHelper
  alias Postgrex.Connection, as: P

  setup do
    opts = [ database: "postgrex_test" ]
    {:ok, pid} = P.start_link(opts)
    {:ok, [pid: pid]}
  end

  test "rebootstrap", context do
    assert [{42}] = query("SELECT $1::int", [42])
    P.rebootstrap(context.pid)
    assert [{42}] = query("SELECT $1::int", [42])
  end

  test "iodata", context do
    assert [{123}] = query(["S", ?E, ["LEC"|"T"], " ", '123'], [])
  end

  test "decode basic types", context do
    assert [{nil}] = query("SELECT NULL", [])
    assert [{true, false}] = query("SELECT true, false", [])
    assert [{"e"}] = query("SELECT 'e'::char", [])
    assert [{"ẽ"}] = query("SELECT 'ẽ'::char", [])
    assert [{42}] = query("SELECT 42", [])
    assert [{42.0}] = query("SELECT 42::float", [])
    assert [{:NaN}] = query("SELECT 'NaN'::float", [])
    assert [{:inf}] = query("SELECT 'inf'::float", [])
    assert [{:"-inf"}] = query("SELECT '-inf'::float", [])
    assert [{"ẽric"}] = query("SELECT 'ẽric'", [])
    assert [{"ẽric"}] = query("SELECT 'ẽric'::varchar", [])
    assert [{<<1, 2, 3>>}] = query("SELECT '\\001\\002\\003'::bytea", [])
  end

  test "decode numeric", context do
    assert [{Decimal.new("42")}] == query("SELECT 42::numeric", [])
    assert [{Decimal.new("42.0000000000")}] == query("SELECT 42.0::numeric(100, 10)", [])
    assert [{Decimal.new("0.4242")}] == query("SELECT 0.4242", [])
    assert [{Decimal.new("42.4242")}] == query("SELECT 42.4242", [])
    assert [{Decimal.new("12345.12345")}] == query("SELECT 12345.12345", [])
    assert [{Decimal.new("0.00012345")}] == query("SELECT 0.00012345", [])
    assert [{Decimal.new("1000000000.0")}] == query("SELECT 1000000000.0", [])
    assert [{Decimal.new("1000000000.1")}] == query("SELECT 1000000000.1", [])
    assert [{Decimal.new("123456789123456789123456789")}] == query("SELECT 123456789123456789123456789::numeric", [])
    assert [{Decimal.new("123456789123456789123456789.123456789")}] == query("SELECT 123456789123456789123456789.123456789", [])
    assert [{Decimal.new("1.1234500000")}] == query("SELECT 1.1234500000", [])
    assert [{Decimal.new("NaN")}] == query("SELECT 'NaN'::numeric", [])
  end

  test "decode uuid", context do
    uuid = <<160,238,188,153,156,11,78,248,187,109,107,185,189,56,10,17>>
    assert [{^uuid}] = query("SELECT 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'::uuid", [])
  end

  test "decode arrays", context do
    assert [{[]}] = query("SELECT ARRAY[]::integer[]", [])
    assert [{[1]}] = query("SELECT ARRAY[1]", [])
    assert [{[1,2]}] = query("SELECT ARRAY[1,2]", [])
    assert [{[[0],[1]]}] = query("SELECT ARRAY[[0],[1]]", [])
    assert [{[[0]]}] = query("SELECT ARRAY[ARRAY[0]]", [])
  end

  test "decode time", context do
    assert [{%Postgrex.Time{hour: 0, min: 0, sec: 0, timezone: nil}}] =
           query("SELECT time '00:00:00'", [])
    assert [{%Postgrex.Time{hour: 1, min: 2, sec: 3, timezone: nil}}] =
           query("SELECT time '01:02:03'", [])
    assert [{%Postgrex.Time{hour: 23, min: 59, sec: 59, timezone: nil}}] =
           query("SELECT time '23:59:59'", [])
    assert [{%Postgrex.Time{hour: 4, min: 5, sec: 6, timezone: nil}}] =
           query("SELECT time '04:05:06 PST'", [])

    # query("SELECT time '00:00:00.123'", [])
    # query("SELECT time '00:00:00.123456'", [])

    assert [{%Postgrex.Time{hour: 0, min: 0, sec: 0, timezone: %Postgrex.TimeZone{hour: 0, min: 0, sec: 0}}}] =
           query("SELECT timetz '00:00:00 UTC'", [])
    assert [{%Postgrex.Time{hour: 1, min: 2, sec: 3, timezone: %Postgrex.TimeZone{hour: 10, min: 0, sec: 0}}}] =
           query("SELECT timetz '01:02:03+10'", [])
    assert [{%Postgrex.Time{hour: 23, min: 59, sec: 59, timezone: %Postgrex.TimeZone{hour: -10, min: 0, sec: 0}}}] =
           query("SELECT timetz '23:59:59-10'", [])
    assert [{%Postgrex.Time{hour: 4, min: 5, sec: 6, timezone: %Postgrex.TimeZone{hour: -8, min: 0, sec: 0}}}] =
           query("SELECT timetz '04:05:06 PST'", [])
    assert [{%Postgrex.Time{hour: 4, min: 5, sec: 6, timezone: %Postgrex.TimeZone{hour: 1, min: 2, sec: 3}}}] =
           query("SELECT timetz '04:05:06+01:02:03'", [])
    assert [{%Postgrex.Time{hour: 4, min: 5, sec: 6, timezone: %Postgrex.TimeZone{hour: -1, min: 2, sec: 3}}}] =
           query("SELECT timetz '04:05:06-01:02:03'", [])

    # query("SELECT time '00:00:00.123456+100'", [])
  end

  test "decode date", context do
    assert [{%Postgrex.Date{year: 1, month: 1, day: 1}}] =
           query("SELECT date '0001-01-01'", [])
    assert [{%Postgrex.Date{year: 1, month: 2, day: 3}}] =
           query("SELECT date '0001-02-03'", [])
    assert [{%Postgrex.Date{year: 2013, month: 9, day: 23}}] =
           query("SELECT date '2013-09-23'", [])

    assert [{%Postgrex.Date{year: 99, month: 1, day: 8, ad: false}}] =
           query("SELECT date 'January 8, 99 BC'", [])
    assert [{%Postgrex.Date{year: 10000, month: 1, day: 1, ad: true}}] =
           query("SELECT date '10000-1-1'", [])
  end

  test "decode timestamp", context do
    assert [{%Postgrex.Timestamp{year: 2001, month: 1, day: 1, hour: 0, min: 0, sec: 0, ad: true, timezone: nil}}] =
           query("SELECT timestamp '2001-01-01 00:00:00'", [])
    assert [{%Postgrex.Timestamp{year: 2001, month: 1, day: 1, hour: 0, min: 0, sec: 0, ad: false, timezone: nil}}] =
           query("SELECT timestamp '2001-01-01 00:00:00 BC'", [])
    assert [{%Postgrex.Timestamp{year: 2013, month: 9, day: 23, hour: 14, min: 4, sec: 37, timezone: nil}}] =
           query("SELECT timestamp '2013-09-23 14:04:37.123'", [])
    assert [{%Postgrex.Timestamp{year: 2013, month: 9, day: 23, hour: 14, min: 4, sec: 37, timezone: nil}}] =
           query("SELECT timestamp '2013-09-23 14:04:37 PST'", [])

    :ok = query("SET TIMEZONE = '0'", [])
    assert [{%Postgrex.Timestamp{year: 2001, month: 1, day: 1, hour: 0, min: 0, sec: 0, timezone: %Postgrex.TimeZone{hour: 0, min: 0, sec: 0}}}] =
           query("SELECT timestamptz '2001-01-01 00:00:00'", [])

    :ok = query("SET TIMEZONE = '5'", [])
    assert [{%Postgrex.Timestamp{year: 2013, month: 9, day: 23, hour: 14, min: 4, sec: 37, timezone: %Postgrex.TimeZone{hour: 5, min: 0, sec: 0}}}] =
           query("SELECT timestamptz '2013-09-23 14:04:37.123'", [])


    :ok = query("SET TIMEZONE = '-01:02'", [])
    assert [{%Postgrex.Timestamp{year: 2013, month: 9, day: 23, hour: 14, min: 4, sec: 37, timezone: %Postgrex.TimeZone{hour: 1, min: 2, sec: 0}}}] =
           query("SELECT timestamptz '2013-09-23 14:04:37'", [])

    :ok = query("SET TIMEZONE = '+01:02'", [])
    assert [{%Postgrex.Timestamp{year: 2013, month: 9, day: 23, hour: 14, min: 4, sec: 37, timezone: %Postgrex.TimeZone{hour: -1, min: 2, sec: 0}}}] =
           query("SELECT timestamptz '2013-09-23 14:04:37.123'", [])

  end

  test "decode interval", context do
    assert [{%Postgrex.Interval{year: 0, month: 0, day: 0, hour: 0, min: 0, sec: 0}}] =
           query("SELECT interval '0'", [])
    assert [{%Postgrex.Interval{year: 0, month: 0, day: 100, hour: 0, min: 0, sec: 0}}] =
           query("SELECT interval '100 days'", [])
    assert [{%Postgrex.Interval{year: 0, month: 0, day: 100, hour: 0, min: 0, sec: 0}}] =
           query("SELECT interval '100 days'", [])
    assert [{%Postgrex.Interval{year: 0, month: 0, day: 0, hour: 50, min: 0, sec: 0}}] =
           query("SELECT interval '50 hours'", [])
    assert [{%Postgrex.Interval{year: 0, month: 0, day: 0, hour: 0, min: 0, sec: 1}}] =
           query("SELECT interval '1 second'", [])
    assert [{%Postgrex.Interval{year: 1, month: 2, day: 40, hour: 3, min: 2, sec: 0}}] =
           query("SELECT interval '1 year 2 months 40 days 3 hours 2 minutes'", [])
  end

  test "decode record", context do
    assert [{{1, "2"}}] = query("SELECT (1, '2')::composite1", [])
    assert [{[{1, "2"}]}] = query("SELECT ARRAY[(1, '2')::composite1]", [])
  end

  @tag min_pg_version: "9.2"
  test "decode range", context do
    assert [{{2,4}}] = query("SELECT '(1,5)'::int4range", [])
    assert [{{1,6}}] = query("SELECT '[1,6]'::int4range", [])
    assert [{{:"-inf",4}}] = query("SELECT '(,5)'::int4range", [])
    assert [{{1,:inf}}] = query("SELECT '[1,)'::int4range", [])

    assert [{{3,7}}] = query("SELECT '(2,8)'::int8range", [])
    assert [{{2,4}}] = query("SELECT '[2,4]'::int8range", [])
    assert [{{:"-inf",3}}] = query("SELECT '(,4)'::int8range", [])
    assert [{{7,:inf}}] = query("SELECT '(6,]'::int8range", [])

    assert [{{Decimal.new("1.0"),Decimal.new("5.999")}}] == query("SELECT numrange(1.0,5.999)", [])
    assert [{{Decimal.new("1.0"),Decimal.new("5.999")}}] == query("SELECT '[1.0,5.999]'::numrange", [])
    assert [{{:"-inf",Decimal.new("1.0000000001")}}] == query("SELECT numrange(NULL,1.0000000001)", [])
    assert [{{Decimal.new("99999999999.9"),:inf}}] == query("SELECT '[99999999999.9,]'::numrange", [])

    # assert [{{{2014,1,1},{2014,12,30}}}] = query("SELECT '[1-1-2014,12-31-2014)'::daterange", [])
    # assert [{{{2014,1,2},{2014,12,31}}}] = query("SELECT '(1-1-2014,12-31-2014]'::daterange", [])
    # assert [{{:"-inf",{2014,12,30}}}] = query("SELECT '(,12-31-2014)'::daterange", [])
    # assert [{{{2014,1,2},:inf}}] = query("SELECT '(1-1-2014,]'::daterange", [])

    # assert [{{{{2014,1,1},{12,0,0}},{{2014,12,31},{12,0,0}}}}] = query("SELECT '[1-1-2014 12:00:00, 12-31-2014 12:00:00)'::tsrange", [])
    # assert [{{{{2014,1,1},{12,0,0}},{{2014,12,31},{12,0,0}}}}] = query("SELECT '(1-1-2014 12:00:00, 12-31-2014 12:00:00]'::tsrange", [])
    # assert [{{:"-inf",{{2014,12,31},{12,0,0}}}}] = query("SELECT '[,12-31-2014 12:00:00)'::tsrange", [])
    # assert [{{{{2014,1,1},{12,0,0}},:inf}}] = query("SELECT '[1-1-2014 12:00:00,)'::tsrange", [])

    # assert [{{{{2014,1,1},{20,0,0}},{{2014,12,31},{20,0,0}}}}] = query("SELECT '[1-1-2014 12:00:00-800, 12-31-2014 12:00:00-800)'::tstzrange", [])
    # assert [{{:"-inf",{{2014,12,31},{8,0,0}}}}] = query("SELECT '[,12-31-2014 12:00:00+400]'::tstzrange", [])
    # assert [{{{{2014,1,1},{16,0,0}},:inf}}] = query("SELECT '(1-1-2014 12:00:00-4:00:00,]'::tstzrange", [])
  end

  test "encode basic types", context do
    assert [{nil, nil}] = query("SELECT $1::text, $2::int", [nil, nil])
    assert [{true, false}] = query("SELECT $1::bool, $2::bool", [true, false])
    assert [{"ẽ"}] = query("SELECT $1::char", ["ẽ"])
    assert [{42}] = query("SELECT $1::int", [42])
    assert [{42.0, 43.0}] = query("SELECT $1::float, $2::float", [42, 43.0])
    assert [{:NaN}] = query("SELECT $1::float", [:NaN])
    assert [{:inf}] = query("SELECT $1::float", [:inf])
    assert [{:"-inf"}] = query("SELECT $1::float", [:"-inf"])
    assert [{"ẽric"}] = query("SELECT $1::varchar", ["ẽric"])
    assert [{<<1, 2, 3>>}] = query("SELECT $1::bytea", [<<1, 2, 3>>])
  end

  test "encode numeric", context do
    nums = [
      "42",
      "0.4242",
      "42.4242",
      "0.00012345",
      "1000000000",
      "1000000000.0",
      "123456789123456789123456789",
      "123456789123456789123456789.123456789",
      "1.1234500000",
      "1.0000000000",
      "NaN"
    ]

    Enum.each(nums, fn num ->
      dec = Decimal.new(num)
      assert [{dec}] == query("SELECT $1::numeric", [dec])
    end)
  end

  test "encode uuid", context do
    uuid = <<0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15>>
    assert [{^uuid}] = query("SELECT $1::uuid", [uuid])
  end

  test "encode date", context do
    assert [{%Postgrex.Date{year: 1, month: 1, day: 1}}] =
           query("SELECT $1::date", [%Postgrex.Date{year: 1, month: 1, day: 1}])
    assert [{%Postgrex.Date{year: 1, month: 2, day: 3}}] =
           query("SELECT $1::date", [%Postgrex.Date{year: 1, month: 2, day: 3}])
    assert [{%Postgrex.Date{year: 2013, month: 9, day: 23}}] =
           query("SELECT $1::date", [%Postgrex.Date{year: 2013, month: 9, day: 23}])
    assert [{%Postgrex.Date{year: 1999, month: 12, day: 31, ad: true}}] =
           query("SELECT $1::date", [%Postgrex.Date{year: 1999, month: 12, day: 31}])
    assert [{%Postgrex.Date{year: 1999, month: 12, day: 31, ad: false}}] =
           query("SELECT $1::date", [%Postgrex.Date{year: 1999, month: 12, day: 31, ad: false}])
  end

  test "encode time", context do
    assert [{%Postgrex.Time{hour: 0, min: 0, sec: 0, timezone: nil}}] =
           query("SELECT $1::time", [%Postgrex.Time{hour: 0, min: 0, sec: 0}])
    assert [{%Postgrex.Time{hour: 1, min: 2, sec: 3, timezone: nil}}] =
           query("SELECT $1::time", [%Postgrex.Time{hour: 1, min: 2, sec: 3}])
    assert [{%Postgrex.Time{hour: 23, min: 59, sec: 59, timezone: nil}}] =
           query("SELECT $1::time", [%Postgrex.Time{hour: 23, min: 59, sec: 59}])
    assert [{%Postgrex.Time{hour: 4, min: 5, sec: 6, timezone: nil}}] =
           query("SELECT $1::time", [%Postgrex.Time{hour: 4, min: 5, sec: 6}])
  end

  test "encode timestamp", context do
    assert [{%Postgrex.Timestamp{year: 1, month: 1, day: 1, hour: 0, min: 0, sec: 0, timezone: nil}}] =
      query("SELECT $1::timestamp", [%Postgrex.Timestamp{year: 1, month: 1, day: 1, hour: 0, min: 0, sec: 0}])
    assert [{%Postgrex.Timestamp{year: 2013, month: 9, day: 23, hour: 14, min: 4, sec: 37, timezone: nil}}] =
      query("SELECT $1::timestamp", [%Postgrex.Timestamp{year: 2013, month: 9, day: 23, hour: 14, min: 4, sec: 37}])
  end

  test "encode interval", context do
    assert [{%Postgrex.Interval{year: 0, month: 0, day: 0, hour: 0, min: 0, sec: 0}}] =
      query("SELECT $1::interval", [%Postgrex.Interval{year: 0, month: 0, day: 0, hour: 0, min: 0, sec: 0}])
    assert [{%Postgrex.Interval{year: 0, month: 0, day: 0, hour: 0, min: 2, sec: 0}}] =
      query("SELECT $1::interval", [%Postgrex.Interval{year: 0, month: 0, day: 0, hour: 0, min: 2, sec: 0}])
    assert [{%Postgrex.Interval{year: 8, month: 4, day: 0, hour: 0, min: 0, sec: 0}}] =
      query("SELECT $1::interval", [%Postgrex.Interval{year: 0, month: 100, day: 0, hour: 0, min: 0, sec: 0}])
    assert [{%Postgrex.Interval{year: 1, month: 2, day: 40, hour: 3, min: 2, sec: 0}}] =
      query("SELECT $1::interval", [%Postgrex.Interval{year: 1, month: 2, day: 40, hour: 3, min: 2, sec: 0}])
  end

  test "encode arrays", context do
    assert [{[]}] = query("SELECT $1::integer[]", [[]])
    assert [{[1]}] = query("SELECT $1::integer[]", [[1]])
    assert [{[1,2]}] = query("SELECT $1::integer[]", [[1,2]])
    assert [{[[0],[1]]}] = query("SELECT $1::integer[]", [[[0],[1]]])
    assert [{[[0]]}] = query("SELECT $1::integer[]", [[[0]]])
    assert [{[1, nil, 3]}] = query("SELECT $1::integer[]", [[1, nil, 3]])
  end

  test "encode record", context do
    assert [{{1, "2"}}] = query("SELECT $1::composite1", [{1, "2"}])
    assert [{[{1, "2"}]}] = query("SELECT $1::composite1[]", [[{1, "2"}]])
    assert [{{1, nil, 3}}] = query("SELECT $1::composite2", [{1, nil, 3}])
  end

  @tag min_pg_version: "9.2"
  test "encode range", context do
    assert [{{1,3}}] = query("SELECT $1::int4range", [{1,3}])
    assert [{{:"-inf",5}}] = query("SELECT $1::int4range", [{:"-inf",5}])
    assert [{{3,:inf}}] = query("SELECT $1::int4range", [{3,:inf}])

    assert [{{2,9}}] = query("SELECT $1::int8range", [{2,9}])
    assert [{{:"-inf",3}}] = query("SELECT $1::int8range", [{:"-inf",3}])
    assert [{{6,:inf}}] = query("SELECT $1::int8range", [{6,:inf}])

    assert [{{Decimal.new("0.1"),Decimal.new("9.9")}}] == query("SELECT $1::numrange", [{Decimal.new("0.1"),Decimal.new("9.9")}])
    assert [{{:"-inf",Decimal.new("99999.99999")}}] == query("SELECT $1::numrange", [{:"-inf",Decimal.new("99999.99999")}])
    assert [{{Decimal.new("0.000000001"),:inf}}] == query("SELECT $1::numrange", [{Decimal.new("0.000000001"),:inf}])

    # assert [{{{2014,1,1},{2014,12,31}}}] = query("SELECT $1::daterange", [{{2014,1,1},{2014,12,31}}])
    # assert [{{:"-inf",{2014,12,31}}}] = query("SELECT $1::daterange", [{:"-inf",{2014,12,31}}])
    # assert [{{{2014,1,1},:inf}}] = query("SELECT $1::daterange", [{{2014,1,1},:inf}])

    # assert [{{{{2014,1,1},{12,0,0}},{{2014,12,31},{12,0,0}}}}] = query("SELECT $1::tsrange", [{{{2014,1,1},{12,0,0}},{{2014,12,31},{12,0,0}}}])
    # assert [{{:"-inf",{{2014,12,31},{12,0,0}}}}] = query("SELECT $1::tsrange", [{:"-inf",{{2014,12,31},{12,0,0}}}])
    # assert [{{{{2014,1,1},{12,0,0}},:inf}}] = query("SELECT $1::tsrange", [{{{2014,1,1},{12,0,0}},:inf}])

    # assert [{{{{2014,1,1},{12,0,0}},{{2014,12,31},{12,0,0}}}}] = query("SELECT $1::tstzrange", [{{{2014,1,1},{12,0,0}},{{2014,12,31},{12,0,0}}}])
    # assert [{{:"-inf",{{2014,12,31},{12,0,0}}}}] = query("SELECT $1::tstzrange", [{:"-inf",{{2014,12,31},{12,0,0}}}])
    # assert [{{{{2014,1,1},{12,0,0}},:inf}}] = query("SELECT $1::tstzrange", [{{{2014,1,1},{12,0,0}},:inf}])
  end

  test "fail on encode arrays", context do
    assert_raise ArgumentError, "nested lists must have lists with matching lengths", fn ->
      query("SELECT $1::integer[]", [[[1], [1,2]]])
    end
    assert [{42}] = query("SELECT 42", [])
  end

  test "fail on encode wrong value", context do
    assert_raise FunctionClauseError, fn ->
      query("SELECT $1::integer", ["123"])
    end
    assert_raise FunctionClauseError, fn ->
      query("SELECT $1::text", [4.0])
    end
    assert [{42}] = query("SELECT 42", [])
  end

  test "non data statement", context do
    assert :ok = query("BEGIN", [])
    assert :ok = query("COMMIT", [])
  end

  test "result struct", context do
    assert {:ok, res} = P.query(context[:pid], "SELECT 123 AS a, 456 AS b", [])
    assert %Postgrex.Result{} = res
    assert res.command == :select
    assert res.columns == ["a", "b"]
    assert res.num_rows == 1
  end

  test "error record", context do
    assert {:error, %Postgrex.Error{}} = P.query(context[:pid], "SELECT 123 + 'a'", [])
  end

  test "multi row result", context do
    assert {:ok, res} = P.query(context[:pid], "VALUES (1, 2), (3, 4)", [])
    assert res.num_rows == 2
    assert res.rows == [{1, 2}, {3, 4}]
  end

  test "insert", context do
    :ok = query("CREATE TABLE test (id int, text text)", [])
    [] = query("SELECT * FROM test", [])
    :ok = query("INSERT INTO test VALUES ($1, $2)", [42, "fortytwo"], [])
    [{42, "fortytwo"}] = query("SELECT * FROM test", [])
  end

  test "connection works after failure", context do
    assert %Postgrex.Error{} = query("wat", [])
    assert [{42}] = query("SELECT 42", [])
  end

  test "async test", context do
    self_pid = self
    Enum.each(1..10, fn _ ->
      spawn fn ->
        send self_pid, query("SELECT pg_sleep(0.1)", [])
      end
    end)

     Enum.each(1..10, fn _ ->
      assert_receive [{:void}], 1000
    end)
  end
end
