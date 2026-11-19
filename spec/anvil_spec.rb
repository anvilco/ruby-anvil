# frozen_string_literal: true

require "stringio"

RSpec.describe Anvil do
  it "exposes the template version numbers the API gives a meaning to" do
    expect(Anvil::VERSION_LATEST).to eq(-1)
    expect(Anvil::VERSION_LATEST_PUBLISHED).to eq(-2)
  end

  describe ".prepare_graphql_file" do
    it "takes a path and derives the filename and mimetype from it" do
      upload = described_class.prepare_graphql_file(fixture_path("dummy.pdf"))

      expect(upload).to be_a(Anvil::UploadWithOptions)
      expect(upload.filename).to eq("dummy.pdf")
      expect(upload.mimetype).to eq("application/pdf")
      expect(upload).to be_path
    end

    it "takes a Pathname" do
      upload = described_class.prepare_graphql_file(Pathname.new(fixture_path("dummy.pdf")))

      expect(upload.filename).to eq("dummy.pdf")
      expect(upload.size).to be > 0
    end

    it "takes an open File and derives the filename from its path" do
      File.open(fixture_path("dummy.pdf"), "rb") do |file|
        upload = described_class.prepare_graphql_file(file)

        expect(upload.filename).to eq("dummy.pdf")
        expect(upload).not_to be_path
      end
    end

    it "takes a StringIO when given a filename" do
      upload = described_class.prepare_graphql_file(StringIO.new("bytes"), filename: "contract.pdf")

      expect(upload.filename).to eq("contract.pdf")
      expect(upload.mimetype).to eq("application/pdf")
    end

    it "honors an explicit mimetype over the one the extension implies" do
      upload = described_class.prepare_graphql_file(
        fixture_path("dummy.pdf"),
        filename: "contract.bin",
        mimetype: "application/pdf"
      )

      expect(upload.mimetype).to eq("application/pdf")
    end

    it "falls back to application/octet-stream for an unknown extension" do
      upload = described_class.prepare_graphql_file(StringIO.new("bytes"), filename: "data.unknown")

      expect(upload.mimetype).to eq("application/octet-stream")
    end

    it "refuses an IO with no filename to upload it under" do
      expect { described_class.prepare_graphql_file(StringIO.new("bytes")) }
        .to raise_error(Anvil::ConfigurationError, /`filename:` must be provided/)
    end

    it "uploads an IO with no filename anyway when told to ignore the check" do
      upload = described_class.prepare_graphql_file(StringIO.new("bytes"), ignore_filename_validation: true)

      expect(upload.filename).to be_nil
    end

    it "refuses a path that does not exist" do
      expect { described_class.prepare_graphql_file("/no/such/file.pdf") }
        .to raise_error(Anvil::ConfigurationError, %r{No file at "/no/such/file.pdf"})
    end

    it "refuses something that is neither a path nor an IO" do
      expect { described_class.prepare_graphql_file(42) }
        .to raise_error(Anvil::ConfigurationError, /takes a path or an IO, not a Integer/)
    end

    it "keeps any other options on the upload" do
      upload = described_class.prepare_graphql_file(fixture_path("dummy.pdf"), some_option: "kept")

      expect(upload.options[:some_option]).to eq("kept")
    end
  end

  describe Anvil::UploadWithOptions do
    it "reads a path's bytes through with_io" do
      upload = Anvil.prepare_graphql_file(fixture_path("dummy.pdf"))

      expect(upload.with_io(&:read)).to start_with("%PDF-1.4")
    end

    it "knows the size of a path and of an IO, and not of something with no size" do
      expect(Anvil.prepare_graphql_file(fixture_path("dummy.pdf")).size).to eq(File.size(fixture_path("dummy.pdf")))
      expect(Anvil.prepare_graphql_file(StringIO.new("bytes"), filename: "a.txt").size).to eq(5)
      readable = Class.new { def read; end }.new
      expect(Anvil::UploadWithOptions.new(readable, {}).size).to be_nil
    end

    it "derives a filename from an upload that names its own, the way Rack does" do
      uploaded = Class.new do
        def read
          "bytes"
        end

        def original_filename
          "from-the-browser.pdf"
        end
      end.new

      expect(Anvil.prepare_graphql_file(uploaded).filename).to eq("from-the-browser.pdf")
    end

    it "rewinds an IO before reading it, so it can be sent twice" do
      upload = Anvil.prepare_graphql_file(StringIO.new("bytes"), filename: "a.txt")

      expect(upload.with_io(&:read)).to eq("bytes")
      expect(upload.with_io(&:read)).to eq("bytes")
    end
  end
end
