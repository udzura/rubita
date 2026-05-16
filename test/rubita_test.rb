# frozen_string_literal: true

require "test_helper"

class RubitaTest < Test::Unit::TestCase
  test "VERSION" do
    assert do
      ::Rubita.const_defined?(:VERSION)
    end
  end

  test "transpiles hello_world to bcc-compatible c" do
    source = <<~RUBY
      def hello_world(_ctx)
        bpf_trace_printk("Hello, World!\\n")
        0
      end
    RUBY

    expected = <<~C.chomp
      int hello_world(void *_ctx) {
        bpf_trace_printk("Hello, World!\\n");
        return 0;
      }
    C

    assert_equal(expected, Rubita.transpile(source))
  end

  test "transpiles multiple functions in one source" do
    source = <<~RUBY
      def hello_world(_ctx)
        bpf_trace_printk("Hello, World!\\n")
        0
      end

      def bye_world(_ctx)
        bpf_trace_printk("Bye, World!\\n")
        1
      end
    RUBY

    expected = <<~C.chomp
      int hello_world(void *_ctx) {
        bpf_trace_printk("Hello, World!\\n");
        return 0;
      }

      int bye_world(void *_ctx) {
        bpf_trace_printk("Bye, World!\\n");
        return 1;
      }
    C

    assert_equal(expected, Rubita.transpile(source))
  end

  test "transpiles BPF_HASH DSL and function" do
    source = <<~RUBY
      BPF_HASH :counts, key: :u64, value: :u64, size: 1024

      def hello_world(_ctx)
        bpf_trace_printk("Hello, World!\\n")
        0
      end
    RUBY

    expected = <<~C.chomp
      BPF_HASH(counts, u64, u64, 1024);

      int hello_world(void *_ctx) {
        bpf_trace_printk("Hello, World!\\n");
        return 0;
      }
    C

    assert_equal(expected, Rubita.transpile(source))
  end

  test "transpiles BPF_HASH DSL without explicit size" do
    source = <<~RUBY
      BPF_HASH :counts, key: :u64, value: :u64
    RUBY

    expected = <<~C.chomp
      BPF_HASH(counts, u64, u64);
    C

    assert_equal(expected, Rubita.transpile(source))
  end
end
