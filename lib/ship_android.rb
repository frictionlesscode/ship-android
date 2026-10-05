require "ship_android/decisions"
require "ship_android/ci_gate"

# An app's fastlane/Fastfile calls configure, then `import ShipAndroid::FASTFILE`; every lane reads
# its app-specific values from ShipAndroid.config. See README.md for each key.
module ShipAndroid
  FASTFILE = File.expand_path("ship_android/Fastfile", __dir__)

  Config = Struct.new(:root, :package, :signing_file, :signing_keys, :store_file_base, :test_tasks,
                      :diagnostics_property, :setup_doc, :preflight, keyword_init: true)

  REQUIRED = %i[root package signing_file signing_keys store_file_base test_tasks setup_doc].freeze

  def self.configure(**opts)
    unknown = opts.keys - Config.members
    raise ArgumentError, "Unknown ShipAndroid option(s): #{unknown.join(', ')}" unless unknown.empty?
    missing = REQUIRED.select { |k| opts[k].nil? }
    raise ArgumentError, "ShipAndroid.configure is missing: #{missing.join(', ')}" unless missing.empty?
    raise ArgumentError, "signing_keys must name four keys, store file first" unless opts[:signing_keys].size == 4
    raise ArgumentError, "root #{opts[:root]} is not a directory" unless File.directory?(opts[:root])

    @config = Config.new(**opts)
  end

  def self.config
    @config or raise "ShipAndroid.configure was not called before the lanes ran - see the app's fastlane/Fastfile"
  end
end
