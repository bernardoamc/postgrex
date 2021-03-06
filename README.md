# Postgrex

[![Build Status](https://travis-ci.org/ericmj/postgrex.svg?branch=master)](https://travis-ci.org/ericmj/postgrex)

PostgreSQL driver for Elixir.

Documentation: http://hexdocs.pm/postgrex/

## Usage

Add Postgrex as a dependency in your `mix.exs` file.

```elixir
def deps do
  [{:postgrex, "~> 0.8"} ]
end
```

After you are done, run `mix deps.get` in your shell to fetch and compile Postgrex. Start an interactive Elixir shell with `iex -S mix`.

```iex
iex> {:ok, pid} = Postgrex.Connection.start_link(hostname: "localhost", username: "postgres", password: "postgres", database: "postgres")
{:ok, #PID<0.69.0>}
iex> Postgrex.Connection.query!(pid, "SELECT user_id, text FROM comments", [])
%Postgrex.Result{command: :select, empty?: false, columns: ["user_id", "text"], rows: [{3,"hey"},{4,"there"}], size: 2}}
iex> Postgrex.Connection.query!(pid, "INSERT INTO comments (user_id, text) VALUES (10, 'heya')", [])
%Postgrex.Result{command: :insert, columns: nil, rows: nil, num_rows: 1}}

```

## Features

  * Automatic decoding and encoding of Elixir values to and from PostgreSQL's binary format
  * User defined extensions for encoding and decoding any PostgresSQL type
  * Supports PostgreSQL 8.4, 9.0, 9.1, 9.2, 9.3, and 9.4

## Data representation

    PostgreSQL      Elixir
    ----------      ------
    NULL            nil
    bool            true | false
    char            "é"
    int             42
    float           42.0
    text            "eric"
    bytea           <<42>>
    numeric         #Decimal<42.0> *
    date            %Postgrex.Date{year: 2013, month: 10, day: 12}
    time            %Postgrex.Time{hour: 0, min: 37, sec: 14, msec: 0}
    timestamp(tz)   %Postgrex.Timestamp{year: 2013 month: 10, day: 12, hour: 0, min: 37, sec: 14, msec: 0}
    interval        %Postgrex.Interval{months: 14, days: 40, secs: 10920}
    array           [1, 2, 3]
    composite type  {42, "title", "content"}
    range           %Postgrex.Range{lower: 1, upper: 5}
    uuid            <<160,238,188,153,156,11,78,248,187,109,107,185,189,56,10,17>>

\* [Decimal](http://github.com/ericmj/decimal)

## Extensions

Extensions are used to extend Postgrex' built-in type encoding/decoding.

Below is an example of an extension that supports encoding/decoding Elixir maps
to the Postgres' JSON type.

```elixir
defmodule Extensions.JSON do
  alias Postgrex.TypeInfo

  @behaviour Postgrex.Extension

  def init(_parameters, opts),
    do: Keyword.fetch!(opts, :library)

  def matching(_library),
    do: [type: "json", type: "jsonb"]

  def format(_library),
    do: :binary

  def encode(%TypeInfo{type: "json"}, map, _state, library),
    do: library.encode!(map)
  def encode(%TypeInfo{type: "jsonb"}, map, _state, library),
    do: <<1, library.encode!(map)::binary>>

  def decode(%TypeInfo{type: "json"}, json, _state, library),
    do: library.decode!(json)
  def decode(%TypeInfo{type: "jsonb"}, <<1, json::binary>>, _state, library),
    do: library.decode!(json)
end

Postgrex.Connection.start_link(extensions: [{Extensions.JSON, library: Poison}], ...)
```

## OID type encoding

PostgreSQL's wire protocol supports encoding types either as text or as binary. Unlike most
client libraries Postgrex uses the binary protocol, not the text protocol. This allows for efficient
encoding of types (e.g. 4-byte integers are encoded as 4 bytes, not as a string of digits) and
automatic support for arrays and composite types.

Unfortunately the PostgreSQL binary protocol transports [OID types](http://www.postgresql.org/docs/current/static/datatype-oid.html#DATATYPE-OID-TABLE)
as integers while the text protocol transports them as string of their name, if one exists, and otherwise as integer.

This means you either need to supply oid types as integers or perform an explicit cast (which would
be automatic when using the text protocol) in the query.

```elixir
# Fails since $1 is regclass not text.
query("select nextval($1)", ["some_sequence"])

# Perform an explicit cast, this would happen automatically when using a client library that uses
# the text protocol.
query("select nextval($1::text::regclass)", ["some_sequence"])

# Determine the oid once and store it for later usage. This is the most efficient way, since
# PostgreSQL only has to perform the lookup once. Client libraries using the text protocol do not
# support this.
%{rows: [{sequence_oid}]} = query("select $1::text::regclass", ["some_sequence"])
query("select nextval($1)", [sequence_oid])
```

## Contributing

To contribute you need to compile Postgrex from source and test it:

```
$ git clone https://github.com/ericmj/postgrex.git
$ cd postgrex
$ mix test
```

The tests requires some modifications to your [hba file](http://www.postgresql.org/docs/9.3/static/auth-pg-hba-conf.html). The path to it can be found by running `$ psql -U postgres -c "SHOW hba_file"` in your shell. Put the following above all other configurations (so that they override):

```
host    all             postgrex_md5_pw         127.0.0.1/32    md5
host    all             postgrex_cleartext_pw   127.0.0.1/32    password
```

The server needs to be restarted for the changes to take effect. Additionally you need to setup a Postgres user with the same username as the local user and give it trust or ident in your hba file. Or you can export $PGUSER and $PGPASS before running tests.

## License

   Copyright 2013 Eric Meadows-Jönsson

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
