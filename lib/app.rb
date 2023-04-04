class App
  class Error < StandardError; end
  class SystemNotFound < Error; end

  #

  def self.log s
    puts s.bold
  end

  def self.logv s
    log s if $VERBOSE
  end

  # called from "#{APP_DIR}/app"
  def self.call argv
    setup_liza
    bundle_systems_app Lizarb::APP_DIR

    puts
    Liza.const(:DevBox)[:command].call argv
    puts
  end

  def self.root
    Pathname Dir.pwd
  end

  def self.setup_liza
    require "liza"

    @loaders << loader = Zeitwerk::Loader.new
    loader.tag = Liza.to_s

    # ORDER MATTERS: IGNORE, COLLAPSE, PUSH
    loader.collapse "#{Liza.source_location_radical}/**/*"
    loader.push_dir "#{Liza.source_location_radical}", namespace: Liza

    loader.enable_reloading
    loader.setup
  end

  def self.bundle_systems_app app_dir
    @systems.keys.each do |k|
      key = "#{k}_system"

      require_system key
      klass = Object.const_get key.camelize

      @systems[k] = klass
    end

    @loaders << loader = Zeitwerk::Loader.new

    @systems.each do |k, klass|
      # ORDER MATTERS: IGNORE, COLLAPSE, PUSH
      loader.collapse "#{klass.source_location_radical}/**/*"
      loader.push_dir "#{klass.source_location_radical}", namespace: klass
    end

    app_name = $APP

    # ORDER MATTERS: IGNORE, COLLAPSE, PUSH
    loader.collapse "#{app_dir}/#{app_name}/**/*"
    loader.push_dir "#{app_dir}/#{app_name}" if Dir.exist? "#{app_dir}/#{app_name}"

    loader.enable_reloading
    loader.setup

    @systems.each do |k, klass|
      connect_system k, klass
    end

    @systems.freeze
  end

  # loaders

  @loaders = []
  @mutex = Mutex.new

  def self.reload &block
    @mutex.synchronize do
      @loaders.map &:reload
      yield if block_given?
    end

    true
  end

  def self.eager_load_all
    Zeitwerk::Loader.eager_load_all
  end

  # modes

  @modes = []

  def self.mode mode = nil
    return $MODE if mode.nil?
    @modes << mode.to_sym
  end

  def self.modes
    @modes
  end

  # systems

  @systems = {}

  def self.system key
    raise "locked" if @locked
    @systems[key] = nil
  end

  def self.systems
    @systems
  end

  def self.require_system key
    t = Time.now
    logv "App.system :#{key}"
    require key
    logv "App.system :#{key} takes #{t.diff}s"
  rescue LoadError => e
    def e.backtrace; []; end
    raise SystemNotFound, "FILE #{key}.rb not found on $LOAD_PATH", []
  end

  # parts

  def self.connect_part part_klass, key, system
    t = Time.now
    string = "CONNECTING PART #{part_klass.to_s.rjust 25}.part :#{key}"
    logv string

    klass = if system.nil?
              Liza.const "#{key}_part"
            else
              Liza.const("#{system}_system")
                  .const "#{key}_part"
            end

    if klass.insertion
      part_klass.class_exec &klass.insertion
    end

    if klass.extension
      klass.const_set :Extension, Class.new(Liza::PartExtension)
      klass::Extension.class_exec &klass.extension
    end
    logv "#{string} takes #{t.diff}s"
  end

  # systems

  def self.connect_system key, system_klass
    t = Time.now

    color_system_klass = system_klass.to_s.colorize system_klass.log_color
    color_key = key.to_s.colorize system_klass.log_color

    registrar_index = 0
    system_klass.registrar.each do |string, target_block|
      reg_type, _sep, reg_target = string.to_s.lpartition "_"

      registrar_index += 1

      target_klass = Liza.const reg_target

      if reg_type == "insertion"
        target_klass.class_exec &target_block
      else
        raise "TODO: decide and implement system extension"
      end

      log "CONNECTING SYSTEM PART          #{color_system_klass}.#{reg_type} #{target_klass}"

    end
    log "CONNECTING SYSTEM - #{t.diff}s for #{color_system_klass} to connect to #{registrar_index} system parts"
  end

end
