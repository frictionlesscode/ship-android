require "minitest/autorun"
require "tmpdir"
require "ship_android"

class ConfigTest < Minitest::Test
  def valid(root)
    { root: root, package: "com.example.app", signing_file: "local.properties",
      signing_keys: %w[A B C D], store_file_base: ".", test_tasks: %w[testDebugUnitTest],
      setup_doc: "docs/releasing.md" }
  end

  def test_configure_fills_optional_defaults
    Dir.mktmpdir do |root|
      c = ShipAndroid.configure(**valid(root))
      assert_nil c.diagnostics_property
      assert_nil c.preflight
      assert_same c, ShipAndroid.config
    end
  end

  # Kills: a typo'd key (diagnostic_property) silently meaning "no diagnostics".
  def test_configure_rejects_unknown_keys
    Dir.mktmpdir do |root|
      error = assert_raises(ArgumentError) { ShipAndroid.configure(**valid(root), diagnostic_property: "x") }
      assert_includes error.message, "diagnostic_property"
    end
  end

  def test_configure_requires_every_required_key
    Dir.mktmpdir do |root|
      error = assert_raises(ArgumentError) { ShipAndroid.configure(**valid(root).except(:package)) }
      assert_includes error.message, "package"
    end
  end

  def test_configure_wants_four_signing_keys
    Dir.mktmpdir do |root|
      assert_raises(ArgumentError) { ShipAndroid.configure(**valid(root), signing_keys: %w[A B C]) }
    end
  end

  def test_configure_wants_an_existing_root
    assert_raises(ArgumentError) { ShipAndroid.configure(**valid("/no/such/dir")) }
  end

  def test_fastfile_path_is_absolute
    assert File.absolute_path?(ShipAndroid::FASTFILE)
  end
end
