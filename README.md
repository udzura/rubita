# Rubita

Rubita is a transpiler that converts a restricted Ruby DSL into BCC-compatible C code for eBPF programs.

## Overview

Rubita enables you to write eBPF probes and kernel tracing programs using a Ruby-like syntax, which are then transpiled into BCC (Berkeley Packet Filter Compiler Collection) compatible C code. This makes it easier to write complex eBPF programs while leveraging Ruby's expressiveness.

### Supported Features

- **Map Declarations**: Define eBPF hash maps with `BPF_HASH`
- **Probe Definitions**: Support for `TRACEPOINT_PROBE`, `KFUNC_PROBE`, `KRETFUNC_PROBE`, and `LSM_PROBE`
- **Method Definitions**: Define helper functions with `def`
- **Field Access**: Convert Ruby dot notation (`obj.field`) to C pointer dereference (`obj->field`)
- **String Literals**: Support format strings with proper escaping

## Installation

Add this line to your application's Gemfile:

```bash
gem 'rubita', github: 'udzura/rubita'
```

And then execute:

```bash
bundle install
```

## Basic Conversion

### Hash Map Declaration

**Ruby DSL:**
```ruby
BPF_HASH :events, key: :u64, value: :u64, size: 1024
```

**Generated C:**
```c
BPF_HASH(events, u64, u64, 1024);
```

### Tracepoint Probe

**Ruby DSL:**
```ruby
TRACEPOINT_PROBE :syscalls, :sys_enter_open do
  bpf_trace_printk("open syscall\n")
  0
end
```

**Generated C:**
```c
TRACEPOINT_PROBE(syscalls, sys_enter_open) {
  bpf_trace_printk("open syscall\n");
  return 0;
}
```

### Kernel Function Probe

**Ruby DSL:**
```ruby
KFUNC_PROBE :vfs_read do
  bpf_trace_printk("Reading file: %d\n", args.got_bits)
  0
end
```

**Generated C:**
```c
KFUNC_PROBE(vfs_read) {
  bpf_trace_printk("Reading file: %d\n", args->got_bits);
  return 0;
}
```

### Helper Functions

**Ruby DSL:**
```ruby
def print_event(_ctx)
  bpf_trace_printk("Event occurred\n")
  0
end
```

**Generated C:**
```c
int print_event(void *_ctx) {
  bpf_trace_printk("Event occurred\n");
  return 0;
}
```

## Usage

```ruby
require 'rubita'

ruby_code = <<~RUBY
  BPF_HASH :counts, key: :u64, value: :u64, size: 10

  TRACEPOINT_PROBE :syscalls, :sys_enter_openat do
    bpf_trace_printk("openat\n")
    0
  end
RUBY

c_code = Rubita.transpile(ruby_code)
puts c_code
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/udzura/rubita.

