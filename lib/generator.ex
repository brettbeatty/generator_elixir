defmodule Generator do
  defmacro generator(start, block) do
    {acc, initial} =
      case start do
        {:<-, _meta, [acc, initial]} ->
          {acc, initial}

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
          {next_block, acc}

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
        fn unquote(acc) -> unquote(next_block) end,
        fn unquote(acc) -> unquote(after_block) end
      )
    end
  end
end
