defmodule GeneratorTest do
  use ExUnit.Case, async: true
  import Generator, only: [generator: 2]
  doctest Generator, import: true

  defmacrop assert_compile_error(message, do: block) do
    quote bind_quoted: [message: message, block: Macro.escape(block)] do
      new_block =
        quote do
          import Generator

          unquote(block)
        end

      exception = assert_raise CompileError, fn -> Code.eval_quoted(new_block) end
      assert Exception.message(exception) =~ message
    end
  end

  defp flush_mailbox do
    messages =
      generator nil <- nil do
        receive do
          message ->
            {[message], nil}
        after
          0 ->
            {:halt, nil}
        end
      end

    Enum.to_list(messages)
  end

  describe "generator/2" do
    test "success: can create simple enumerable" do
      my_generator =
        generator x <- ?c do
          if x >= ?a do
            {[x], x - 1}
          else
            {:halt, x}
          end
        end

      assert Enum.to_list(my_generator) == 'cba'
    end

    test "success: can create infinite streams" do
      my_generator =
        generator x <- ?a do
          {[x], x + 1}
        end

      assert Enum.take(my_generator, 3) == 'abc'
    end

    test "success: can yield multiple elements every step" do
      my_generator =
        generator x <- ?a do
          {[x, x - ?a + ?A], x + 1}
        end

      assert Enum.take(my_generator, 5) == 'aAbBc'
    end

    test "success: can yield no elements in a step" do
      my_generator =
        generator x <- ?a do
          if rem(x, 2) == 0 do
            {[], x + 1}
          else
            {[x], x + 1}
          end
        end

      assert Enum.take(my_generator, 3) == 'ace'
    end

    test "success: lazily evaluates initial state" do
      my_generator =
        generator x <- send(self(), ?a) do
          {[x], x + 1}
        end

      refute_received ?a

      Enum.take(my_generator, 3)

      assert_received ?a
    end

    test "success: lazily evaluates each step" do
      my_generator =
        generator x <- ?a do
          send(self(), x)
          {[x], x + 1}
        end

      refute_received ?a

      Enum.take(my_generator, 3)

      assert_received ?a
      assert_received ?b
      assert_received ?c
      refute_received ?d
    end

    test "success: allows cleanup with :after" do
      my_generator =
        generator x <- ?a do
          {[x], x + 1}
        after
          send(self(), x)
        end

      refute_received ?d

      Enum.take(my_generator, 3)

      refute_received ?a
      refute_received ?b
      refute_received ?c
      assert_received ?d
    end

    test "success: cleanup also works with self-halted generator" do
      my_generator =
        generator x <- ?a do
          if x <= ?c do
            {[x], x + 1}
          else
            # alter state here to show it in :after
            {:halt, <<x>>}
          end
        after
          send(self(), x)
        end

      refute_received "d"

      Enum.to_list(my_generator)

      refute_received ?d
      assert_received "d"
    end

    test "success: cleanup also works with exceptions" do
      my_generator =
        generator x <- ?a do
          if x <= ?c do
            {[x], x + 1}
          else
            raise "a nasty exception"
          end
        after
          send(self(), x)
        end

      refute_received ?d

      assert_raise RuntimeError, "a nasty exception", fn ->
        # don't want to Enum.to_list/1 an infinite stream if raise goes wrong
        Enum.take(my_generator, 4)
      end

      assert_received ?d
    end

    test "success: cleanup also works with exits" do
      my_generator =
        generator x <- ?a do
          if x <= ?c do
            {[x], x + 1}
          else
            exit(:normal)
          end
        after
          send(self(), x)
        end

      refute_received ?d

      assert catch_exit(Enum.take(my_generator, 4)) == :normal

      assert_received ?d
    end

    test "error: fails at runtime if can't match on initial state" do
      my_generator =
        generator {:ok, x} <- ?a do
          {[x], x + 1}
        end

      assert_raise FunctionClauseError, fn ->
        Enum.take(my_generator, 1)
      end
    end

    test "error: fails at runtime if can't match on next state" do
      my_generator =
        generator {:ok, x} <- {:ok, 0} do
          {:error, x + 1}
        end

      assert_raise FunctionClauseError, fn ->
        Enum.take(my_generator, 1)
      end
    end

    test "error: fails if first arg is not left arrow" do
      assert_compile_error ~S(expected <- clause in "generator") do
        generator 5 do
          {:halt, nil}
        end
      end
    end

    test "error: fails with unexpected keywords in block" do
      assert_compile_error ~S(unexpected option :else in "generator") do
        generator x <- 0 do
          {[x], x + 1}
        else
          _ -> {:halt, x}
        end
      end
    end

    test "error: fails without :do block" do
      assert_compile_error ~S(missing :do option in "generator") do
        generator(x <- 0, after: x)
      end
    end
  end
end
