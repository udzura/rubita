# frozen_string_literal: true

module Rubita
  class Transpiler
    def transpile(source)
      sexp = Ripper.sexp(source)
      raise Error, "failed to parse source" if sexp.nil?

      def_node = extract_single_def(sexp)
      function_name = extract_function_name(def_node)
      statements, return_value = extract_body_statements_and_return(def_node)

      c_lines = ["int #{function_name}(void *ctx) {"]
      statements.each do |statement|
        c_lines << "  #{convert_statement(statement)}"
      end
      c_lines << "  return #{return_value};"
      c_lines << "}"
      c_lines.join("\n")
    end

    private

    def extract_single_def(sexp)
      return raise Error, "unexpected program structure" unless sexp[0] == :program

      nodes = sexp[1]
      return raise Error, "source must contain exactly one method definition" unless nodes.is_a?(Array) && nodes.size == 1

      def_node = nodes[0]
      return raise Error, "only def is supported" unless def_node[0] == :def

      def_node
    end

    def extract_function_name(def_node)
      ident = def_node[1]
      return raise Error, "method name is missing" unless ident&.[](0) == :@ident

      ident[1]
    end

    def extract_body_statements_and_return(def_node)
      bodystmt = def_node[3]
      stmts = bodystmt[1]
      return raise Error, "method body is missing" unless stmts.is_a?(Array) && !stmts.empty?

      return_node = stmts.last
      return raise Error, "last expression must be integer literal" unless return_node[0] == :@int

      [stmts[0...-1], return_node[1]]
    end

    def convert_statement(statement)
      case statement[0]
      when :method_add_arg
        convert_method_call(statement)
      else
        raise Error, "unsupported statement: #{statement[0]}"
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
      else
        raise Error, "unsupported argument type: #{arg[0]}"
      end
    end

    def escape_c_string(value)
      value.gsub("\\", "\\\\").gsub('"', '\\"')
    end
  end
end
