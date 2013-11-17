require "yaml"

module Fontcustom
  class Options
    include Utility

    attr_accessor :options

    def initialize(cli_options = {}, manifest_options = {})
      @cli_options = symbolize_hash(cli_options)
      @manifest_options = symbolize_hash(manifest_options)
      parse_options
    end

    private

    def parse_options
      overwrite_examples
      set_config_path
      load_config
      merge_options
      clean_font_name
      set_manifest_path
      set_input_paths
      set_output_paths
      set_template_paths
    end

    # We give Thor fake defaults to generate more useful help messages.
    # Here, we delete any CLI options that match those examples.
    def overwrite_examples
      EXAMPLE_OPTIONS.keys.each do |key|
        @cli_options.delete(key) if @cli_options[key] == EXAMPLE_OPTIONS[key]
      end
      @cli_options = DEFAULT_OPTIONS.dup.merge @cli_options
      @cli_options[:project_root] ||= Dir.pwd
    end

    def set_config_path
      @cli_options[:config] = if @cli_options[:config]
        path = expand_path @cli_options[:config]

        # :config is the path to fontcustom.yml
        if File.exists?(path) && ! File.directory?(path)
          path

        # :config is a dir containing fontcustom.yml
        elsif File.exists? File.join(path, "fontcustom.yml")
          File.join path, "fontcustom.yml"

        else
          raise Fontcustom::Error, "The configuration file wasn't found. Check `#{relative_to_root(path)}` and try again."
        end
      else
        # fontcustom.yml is in the project_root
        if File.exists? File.join(@cli_options[:project_root], "fontcustom.yml")
          File.join @cli_options[:project_root], "fontcustom.yml"

        # config/fontcustom.yml is in the project_root
        elsif File.exists? File.join(@cli_options[:project_root], "config", "fontcustom.yml")
          File.join @cli_options[:project_root], "config", "fontcustom.yml"

        else
          false
        end
      end
    end

    def load_config
      @config_options = {}
      if @cli_options[:config]
        say_message :status, "Loading configuration file at `#{relative_to_root(@cli_options[:config])}`."
        begin
          config = YAML.load File.open(@cli_options[:config])
          if config # empty YAML returns false
            @config_options = symbolize_hash(config)
          else
            say_message :status, "Configuration file was empty. Using defaults."
          end
        rescue Exception => e
          raise Fontcustom::Error, "The configuration file failed to load. Message: #{e.message}"
        end
      else
        say_message :status, "No configuration file set. Generate one with `fontcustom config` to preserve options between compiles."
      end
    end

    def merge_options
      @cli_options.delete_if { |key, val| val == DEFAULT_OPTIONS[key] }
      @options = DEFAULT_OPTIONS.merge(@manifest_options).merge(@config_options).merge(@cli_options)
      @options = methodize_hash @options
    end

    def clean_font_name
      @options[:font_name] = @options[:font_name].strip.gsub(/\W/, "-")
    end

    def set_manifest_path
      @options[:manifest] = if ! @options[:manifest].nil?
        expand_path @options[:manifest]
      elsif @options[:config]
        File.join File.dirname(@options[:config]), ".fontcustom-manifest.json"
      else
        File.join @options[:project_root], ".fontcustom-manifest.json"
      end
    end

    def set_input_paths
      if @options[:input].is_a? Hash
        @options[:input] = symbolize_hash(@options[:input])
        if @options[:input].has_key? :vectors
          @options[:input][:vectors] = expand_path @options[:input][:vectors]
          unless File.directory? @options[:input][:vectors]
            raise Fontcustom::Error, "INPUT[:vectors] should be a directory. Check `#{relative_to_root(@options[:input][:vectors])}` and try again."
          end
        else
          raise Fontcustom::Error, "INPUT (as a hash) should contain a :vectors key."
        end

        if @options[:input].has_key? :templates
          @options[:input][:templates] = expand_path @options[:input][:templates]
          unless File.directory? @options[:input][:templates]
            raise Fontcustom::Error, "INPUT[:templates] should be a directory. Check `#{relative_to_root(@options[:input][:templates])}` and try again."
          end
        else
          @options[:input][:templates] = @options[:input][:vectors]
        end
      else
        input = @options[:input] ? expand_path(@options[:input]) : @options[:project_root]
        unless File.directory? input
          raise Fontcustom::Error, "INPUT (as a string) should be a directory. Check `#{relative_to_root(input)}` and try again."
        end
        @options[:input] = { :vectors => input, :templates => input }
      end

      if Dir[File.join(@options[:input][:vectors], "*.svg")].empty?
        raise Fontcustom::Error, "`#{relative_to_root(@options[:input][:vectors])}` doesn't contain any SVGs."
      end
    end

    def set_output_paths
      if @options[:output].is_a? Hash
        @options[:output] = symbolize_hash(@options[:output])
        raise Fontcustom::Error, "OUTPUT (as a hash) should contain a :fonts key." unless @options[:output].has_key? :fonts

        @options[:output].each do |key, val|
          @options[:output][key] = expand_path val
          if File.exists?(val) && ! File.directory?(val)
            raise Fontcustom::Error, "OUTPUT[:#{key.to_s}] should be a directory, not a file. Check `#{relative_to_root(val)}` and try again."
          end
        end

        @options[:output][:css] ||= @options[:output][:fonts]
        @options[:output][:preview] ||= @options[:output][:fonts]
      else
        if @options[:output].is_a? String
          output = expand_path @options[:output]
          if File.exists?(output) && ! File.directory?(output)
            raise Fontcustom::Error, "OUTPUT should be a directory, not a file. Check `#{relative_to_root(output)}` and try again."
          end
        else
          output = File.join @options[:project_root], @options[:font_name]
          say_message :status, "All generated files will be saved to `#{relative_to_root(output)}/`."
        end

        @options[:output] = {
          :fonts => output,
          :css => output,
          :preview => output
        }
      end
    end

    # Translates shorthand to full path of packages templates, otherwise,
    # it checks input and pwd for the template.
    #
    # Could arguably belong in Generator::Template, however, it's nice to
    # be able to catch template errors before any generator runs.
    def set_template_paths
      template_path = File.join Fontcustom.gem_lib, "templates"

      @options[:templates] = @options[:templates].map do |template|
        case template
        when "preview"
          File.join template_path, "fontcustom-preview.html"
        when "css"
          File.join template_path, "fontcustom.css"
        when "scss"
          File.join template_path, "_fontcustom.scss"
        when "scss-rails"
          File.join template_path, "_fontcustom-rails.scss"
        when "bootstrap"
          File.join template_path, "fontcustom-bootstrap.css"
        when "bootstrap-scss"
          File.join template_path, "_fontcustom-bootstrap.scss"
        when "bootstrap-ie7"
          File.join template_path, "fontcustom-bootstrap-ie7.css"
        when "bootstrap-ie7-scss"
          File.join template_path, "_fontcustom-bootstrap-ie7.scss"
        else
          template = File.expand_path File.join(@options[:input][:templates], template) unless template[0] == "/"
          raise Fontcustom::Error, "The custom template at `#{relative_to_root(template)}` does not exist." unless File.exists? template
          template
        end
      end
    end
  end
end
