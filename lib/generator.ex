defmodule Generator do
  @moduledoc """
  The `generator/2` macro is syntactic sugar on top of `Stream.resource/3`. It's my idea for
  bringing enumerable generators to Elixir.
  """

  @doc """
  Generators allow you to quickly build streams from an initial value or resource.

  Let's start with an example:

      iex> my_generator = generator x <- ?a, do: {[x], x + 1}
      iex> Enum.take(my_generator, 3)
      'abc'

  A generator accepts an initial state (right side of `<-`) and a match (left side of `<-`, often a
  variable) for the initial and subsequent state. Any unpinned variables in the match get bound to
  for each iteration of the generator.

  The `:do` block should return a tuple with two values:
  1. A list of elements to emit from the generator for that iteration or the atom `:halt`.
  2. An updated state.

  The list of emitted elements is flattened into the generator output, so each iteration of the
  generator can emit 0 elements, 1 element, or many elements:

      iex> my_generator =
      ...>   generator x <- ?a do
      ...>     if rem(x, 2) == 0 do
      ...>       {[x, x], x + 1}
      ...>     else
      ...>       {[], x + 1}
      ...>     end
      ...>   end
      iex> Enum.take(my_generator, 5)
      'bbddf'

  You can halt a generator by returning `:halt` instead of a list of elements to emit:

      iex> my_generator =
      ...>   generator x <- ?a do
      ...>     if x <= ?c do
      ...>       {[x], x + 1}
      ...>     else
      ...>       {:halt, x}
      ...>     end
      ...>   end
      iex> Enum.to_list(my_generator)
      'abc'

  ## The `:after` option
  When the generator is operating on a resource (such as an open file), you may need it to clean up
  after itself. You can include code in an `:after` block that gets run once your generator halts,
  even if it halts because of an exception or exit!

  If the generator halts itself, it can specify the state given to the `:after` block:

      iex> my_generator =
      ...>   generator x <- ?a do
      ...>     if x <= ?c do
      ...>       {[x], x + 1}
      ...>     else
      ...>       {:halt, :error}
      ...>     end
      ...>   after
      ...>     send(self(), x)
      ...>   end
      iex> Enum.to_list(my_generator)
      'abc'
      iex> receive do x -> x end
      :error

  Otherwise the `:after` block receives the state that would have been available to the next
  iteration of the generator:

      iex> my_generator = generator x <- ?a, do: {[x], x + 1}, after: send(self(), x)
      iex> Enum.take(my_generator, 3)
      'abc'
      iex> receive do x -> x end
      ?d

  ## Generators produce streams
  Often your generator may not know how many elements to produce. Rather than trying to predict that
  or create situations where a desired length would need passed in, all generators produce streams.
  You can read more about streams in the docs for the `Stream` module, but the general idea is this:
  streams are an enumerable value like lists where the elements are calculated lazily (on demand)
  rather than eagerly.

  This allows you to do interesting things, like creating infinite streams, but with streams there
  are some pitfalls to watch out for.

  When working with infinite streams, it's easy to accidentially attempt a traversal of the entire
  stream, especially with "for" comprehensions and `Enum.to_list/1`:

      # infinite stream
      my_generator = generator x <- ?a, do: {[x], x + 1}

      # unbounded enumeration
      Enum.to_list(my_generator)

  Make sure to always add bounds when consuming infinite streams. If you want a known number of
  elements, `Enum.take/2` is a good option.

  You can also create an infinite stream by accident if your generator reaches a state where there
  are no more elements to emit but your generator won't halt itself:

      # accidental infinite stream
      my_generator =
        generator x <- ?a do
          if x < ?c do
            {[x], x + 1}
          else
            {[], x + 1}
          end
        end

      # unbounded enumeration
      Enum.to_list(my_generator)

  Make sure your generators halt themselves when there are no more elements to emit.

  Another consideration with streams is that because everything is evaluated lazily, a second
  traversal of the stream will duplicate the work done:

      iex> my_generator =
      ...>   generator x <- (send(self(), :start); ?a) do
      ...>     send(self(), x)
      ...>     {[x], x + 1}
      ...>   end
      iex> flush_mailbox()
      []
      iex> Enum.take(my_generator, 2)
      iex> flush_mailbox()
      [:start, ?a, ?b]
      iex> Enum.take(my_generator, 0)
      iex> flush_mailbox()
      []
      iex> Enum.take(my_generator, 1)
      iex> flush_mailbox()
      [:start, ?a]

  If a stream is going to be enumerated more than once, it's often better to collect it into a list
  or other collection and pass that to the places it'll be used.
  """
  defmacro generator(start, block) do
    {state, initial} =
      case start do
        {:<-, _meta, [state, initial]} ->
          {state, initial}

        _ ->
          raise CompileError,
            description: ~S(expected <- clause in "generator"),
            file: __CALLER__.file,
            line: __CALLER__.line
      end

    {next_block, after_block} =
      case block do
        [do: next_block, after: after_block] ->
          {next_block, after_block}

        [do: next_block] ->
          {next_block, state}

        [{:do, _}, {opt, _} | _] ->
          raise CompileError,
            description: ~s(unexpected option #{inspect(opt)} in "generator"),
            file: __CALLER__.file,
            line: __CALLER__.line

        _ ->
          raise CompileError,
            description: ~S(missing :do option in "generator"),
            file: __CALLER__.file,
            line: __CALLER__.line
      end

    quote do
      Stream.resource(
        fn -> unquote(initial) end,
        fn unquote(state) -> unquote(next_block) end,
        fn unquote(state) -> unquote(after_block) end
      )
    end
  end
end
