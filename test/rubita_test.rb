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

  test "transpiles TRACEPOINT_PROBE DSL" do
    source = <<~RUBY
      TRACEPOINT_PROBE :syscalls, :sys_enter_openat do |_ctx|
        bpf_trace_printk("openat\\n")
        0
      end
    RUBY

    expected = <<~C.chomp
      TRACEPOINT_PROBE(syscalls, sys_enter_openat) {
        bpf_trace_printk("openat\\n");
        return 0;
      }
    C

    assert_equal(expected, Rubita.transpile(source))
  end

  test "transpiles BPF_HASH and TRACEPOINT_PROBE together" do
    source = <<~RUBY
      BPF_HASH :counts, key: :u64, value: :u64, size: 10

      TRACEPOINT_PROBE :syscalls, :sys_enter_openat do |_ctx|
        bpf_trace_printk("openat\\n")
        0
      end
    RUBY

    expected = <<~C.chomp
      BPF_HASH(counts, u64, u64, 10);

      TRACEPOINT_PROBE(syscalls, sys_enter_openat) {
        bpf_trace_printk("openat\\n");
        return 0;
      }
    C

    assert_equal(expected, Rubita.transpile(source))
  end

  test "transpiles KFUNC_PROBE DSL" do
    source = <<~RUBY
      KFUNC_PROBE :vfs_read do |_ctx|
        bpf_trace_printk("kfunc\\n")
        0
      end
    RUBY

    expected = <<~C.chomp
      KFUNC_PROBE(vfs_read) {
        bpf_trace_printk("kfunc\\n");
        return 0;
      }
    C

    assert_equal(expected, Rubita.transpile(source))
  end

  test "transpiles KRETFUNC_PROBE DSL" do
    source = <<~RUBY
      KRETFUNC_PROBE :vfs_read do |_ctx|
        bpf_trace_printk("kretfunc\\n")
        0
      end
    RUBY

    expected = <<~C.chomp
      KRETFUNC_PROBE(vfs_read) {
        bpf_trace_printk("kretfunc\\n");
        return 0;
      }
    C

    assert_equal(expected, Rubita.transpile(source))
  end

  test "transpiles LSM_PROBE DSL" do
    source = <<~RUBY
      LSM_PROBE :file_open do |_ctx|
        bpf_trace_printk("lsm\\n")
        0
      end
    RUBY

    expected = <<~C.chomp
      LSM_PROBE(file_open) {
        bpf_trace_printk("lsm\\n");
        return 0;
      }
    C

    assert_equal(expected, Rubita.transpile(source))
  end

  test "transpiles TRACEPOINT_PROBE with dotted field access argument" do
    source = <<~RUBY
      TRACEPOINT_PROBE :random, :urandom_read do |_ctx|
        bpf_trace_printk("%d\\n", args.got_bits)
        0
      end
    RUBY

    expected = <<~C.chomp
      TRACEPOINT_PROBE(random, urandom_read) {
        bpf_trace_printk("%d\\n", args->got_bits);
        return 0;
      }
    C

    assert_equal(expected, Rubita.transpile(source))
  end

  test "transpiles TRACEPOINT_PROBE without block parameter" do
    source = <<~RUBY
      TRACEPOINT_PROBE :random, :urandom_read do
        bpf_trace_printk("%d\\n", args.got_bits)
        0
      end
    RUBY

    expected = <<~C.chomp
      TRACEPOINT_PROBE(random, urandom_read) {
        bpf_trace_printk("%d\\n", args->got_bits);
        return 0;
      }
    C

    assert_equal(expected, Rubita.transpile(source))
  end
end
