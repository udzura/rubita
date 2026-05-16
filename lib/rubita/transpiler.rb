# frozen_string_literal: true

module Rubita
  class Transpiler
    def transpile(source)
      sexp = Ripper.sexp(source)
      raise Error, "failed to parse source" if sexp.nil?

      nodes = extract_program_nodes(sexp)

      converted = nodes.map do |node|
        case node[0]
        when :def
          convert_definition(node)
        when :command
          convert_top_level_command(node)
        when :method_add_block
          convert_top_level_block(node)
        else
          raise Error, "unsupported top-level node: #{node[0]}"
        end
      end

      converted.join("\n\n")
    end

    private

    def extract_program_nodes(sexp)
      return raise Error, "unexpected program structure" unless sexp[0] == :program

      nodes = sexp[1]
      return raise Error, "source must contain nodes" unless nodes.is_a?(Array) && !nodes.empty?

      nodes
    end

    def convert_top_level_command(node)
      ident = node[1]
      return raise Error, "unsupported command format" unless [:@ident, :@const].include?(ident&.[](0))

      case ident[1]
      when "BPF_HASH"
        convert_hashmap_command(node)
      else
        raise Error, "unsupported command: #{ident[1]}"
      end
    end

    def convert_top_level_block(node)
      call_node = node[1]
      block_node = node[2]

      return raise Error, "unsupported block call" unless call_node&.[](0) == :command

      ident = call_node[1]
      return raise Error, "unsupported block command format" unless ident&.[](0) == :@const

      case ident[1]
      when "TRACEPOINT_PROBE"
        convert_probe_block(call_node, block_node, "TRACEPOINT_PROBE", 2)
      when "KFUNC_PROBE"
        convert_probe_block(call_node, block_node, "KFUNC_PROBE", 1)
      when "KRETFUNC_PROBE"
        convert_probe_block(call_node, block_node, "KRETFUNC_PROBE", 1)
      when "LSM_PROBE"
        convert_probe_block(call_node, block_node, "LSM_PROBE", 1)
      else
        raise Error, "unsupported block command: #{ident[1]}"
      end
    end

    def convert_probe_block(call_node, block_node, macro_name, arg_count)
      args_add_block = call_node[2]
      return raise Error, "unsupported #{macro_name} args" unless args_add_block&.[](0) == :args_add_block

      raw_args = args_add_block[1]
      return raise Error, "#{macro_name} requires #{arg_count} arguments" unless raw_args.is_a?(Array) && raw_args.size == arg_count

      macro_args = raw_args.map { |arg| convert_symbol_literal(arg) }

      return raise Error, "#{macro_name} requires do ... end block" unless block_node&.[](0) == :do_block
      bodystmt = block_node[2]
      statements, return_value = extract_body_statements_and_return_from_bodystmt(bodystmt)

      c_lines = ["#{macro_name}(#{macro_args.join(', ')}) {"]
      statements.each do |statement|
        c_lines << "  #{convert_statement(statement)}"
      end
      c_lines << "  return #{return_value};"
      c_lines << "}"
      c_lines.join("\n")
    end

    def convert_hashmap_command(node)
      args_add_block = node[2]
      return raise Error, "unsupported hashmap args" unless args_add_block[0] == :args_add_block

      raw_args = args_add_block[1]
      map_name = convert_symbol_literal(raw_args[0])

      options_node = raw_args[1]
      return raise Error, "hashmap options are required" unless options_node&.[](0) == :bare_assoc_hash

      options = extract_assoc_hash(options_node)
      key_type = options["key"] || (raise Error, "hashmap key is required")
      value_type = options["value"] || (raise Error, "hashmap value is required")
      size = options["size"]

      if size
        "BPF_HASH(#{map_name}, #{key_type}, #{value_type}, #{size});"
      else
        "BPF_HASH(#{map_name}, #{key_type}, #{value_type});"
      end
    end

    def extract_assoc_hash(node)
      pairs = node[1]
      return raise Error, "invalid hashmap options" unless pairs.is_a?(Array)

      pairs.each_with_object({}) do |pair, acc|
        return raise Error, "invalid hashmap option pair" unless pair[0] == :assoc_new

        label_node = pair[1]
        value_node = pair[2]
        return raise Error, "invalid hashmap option key" unless label_node[0] == :@label

        key = label_node[1].delete_suffix(":")
        value = convert_hashmap_option_value(value_node)
        acc[key] = value
      end
    end

    def convert_hashmap_option_value(node)
      case node[0]
      when :symbol_literal
        convert_symbol_literal(node)
      when :@int
        node[1]
      else
        raise Error, "unsupported hashmap option value: #{node[0]}"
      end
    end

    def convert_symbol_literal(node)
      symbol_ident = node.dig(1, 1)
      return raise Error, "unsupported symbol literal" unless symbol_ident&.[](0) == :@ident

      symbol_ident[1]
    end

    def convert_definition(def_node)
      function_name = extract_function_name(def_node)
      statements, return_value = extract_body_statements_and_return(def_node)

      c_lines = ["int #{function_name}(void *_ctx) {"]
      statements.each do |statement|
        c_lines << "  #{convert_statement(statement)}"
      end
      c_lines << "  return #{return_value};"
      c_lines << "}"
      c_lines.join("\n")
    end

    def extract_function_name(def_node)
      ident = def_node[1]
      return raise Error, "method name is missing" unless ident&.[](0) == :@ident

      ident[1]
    end

    def extract_body_statements_and_return(def_node)
      bodystmt = def_node[3]
      extract_body_statements_and_return_from_bodystmt(bodystmt)
    end

    def extract_body_statements_and_return_from_bodystmt(bodystmt)
      stmts = bodystmt[1]
      return raise Error, "method body is missing" unless stmts.is_a?(Array) && !stmts.empty?

      return_node = stmts.last
      return raise Error, "last expression must be integer literal" unless return_node[0] == :@int

      [stmts[0...-1], return_node[1]]
    end

    def convert_statement(statement)
      case statement[0]
      when :method_add_arg
        convert_method_call_statement(statement)
      else
        raise Error, "unsupported statement: #{statement[0]}"
      end
    end

    def convert_method_call_statement(statement)
      call_target = statement[1]
      arg_part = statement[2]

      case call_target[0]
      when :fcall
        convert_fcall_statement(call_target, arg_part)
      when :call
        convert_call_statement(call_target, arg_part)
      else
        raise Error, "unsupported call target type: #{call_target[0]}"
      end
    end

    def convert_fcall_statement(call_target, arg_part)
      method_ident = call_target[1]
      return raise Error, "unsupported method identifier" unless method_ident[0] == :@ident

      args = extract_args(arg_part)
      "#{method_ident[1]}(#{args.join(', ')});"
    end

    def convert_call_statement(call_target, arg_part)
      receiver = call_target[1]
      method_name_node = call_target[3]

      return raise Error, "unsupported call method name" unless method_name_node&.[](0) == :@ident

      method_name = method_name_node[1]

      # Check if receiver is a global variable
      if receiver&.[](0) == :var_ref && receiver[1]&.[](0) == :@gvar
        gvar_name = receiver[1][1].delete_prefix("$")
        args = extract_args_with_reference(arg_part)
        "#{gvar_name}.#{method_name}(#{args.join(', ')});"
      else
        raise Error, "unsupported call receiver type: #{receiver&.[](0)}"
      end
    end

    def convert_method_call(statement)
      call_target = statement[1]
      arg_part = statement[2]

      return raise Error, "unsupported call target" unless call_target[0] == :fcall
      method_ident = call_target[1]
      return raise Error, "unsupported method identifier" unless method_ident[0] == :@ident

      args = extract_args(arg_part)
      "#{method_ident[1]}(#{args.join(', ')});"
    end

    def extract_args_with_reference(arg_part)
      return raise Error, "unsupported arg format" unless arg_part[0] == :arg_paren

      args_add_block = arg_part[1]
      return raise Error, "unsupported arg list" unless args_add_block[0] == :args_add_block

      raw_args = args_add_block[1]
      raw_args.map { |arg| convert_arg_with_reference(arg) }
    end

    def convert_arg_with_reference(arg)
      case arg[0]
      when :vcall
        arg_ident = arg[1]
        return raise Error, "unsupported variable call" unless arg_ident&.[](0) == :@ident
        "&#{arg_ident[1]}"
      when :string_literal
        string_content = arg.dig(1, 1)
        return raise Error, "unsupported string format" unless string_content&.[](0) == :@tstring_content

        escaped = escape_c_string(string_content[1])
        %Q("#{escaped}")
      when :call
        convert_call_arg(arg)
      else
        raise Error, "unsupported argument type for reference: #{arg[0]}"
      end
    end

    def extract_args(arg_part)
      return raise Error, "unsupported arg format" unless arg_part[0] == :arg_paren

      args_add_block = arg_part[1]
      return raise Error, "unsupported arg list" unless args_add_block[0] == :args_add_block

      raw_args = args_add_block[1]
      raw_args.map { |arg| convert_arg(arg) }
    end

    def convert_arg(arg)
      case arg[0]
      when :string_literal
        string_content = arg.dig(1, 1)
        return raise Error, "unsupported string format" unless string_content&.[](0) == :@tstring_content

        escaped = escape_c_string(string_content[1])
        %Q("#{escaped}")
      when :call
        convert_call_arg(arg)
      else
        raise Error, "unsupported argument type: #{arg[0]}"
      end
    end

    def convert_call_arg(call_node)
      receiver = call_node[1]
      method_name_node = call_node[3]

      return raise Error, "unsupported call receiver" unless receiver&.[](0) == :vcall
      receiver_ident = receiver[1]
      return raise Error, "unsupported receiver identifier" unless receiver_ident&.[](0) == :@ident

      return raise Error, "unsupported method name" unless method_name_node&.[](0) == :@ident

      receiver_name = receiver_ident[1]
      method_name = method_name_node[1]
      "#{receiver_name}->#{method_name}"
    end

    def escape_c_string(value)
      value.gsub("\\", "\\\\").gsub('"', '\\"')
    end
  end
end
