# frozen_string_literal: true

module Anvil
  module Payloads
    # The body of a {Anvil::Client#generate_pdf} call.
    #
    # `type` picks the input: "markdown" (the API's default) takes an Array of
    # content Hashes in `data`, while "html" takes a Hash of `html` and `css`.
    #
    # @see https://www.useanvil.com/docs/api/generate-pdf
    class GeneratePdf < Base
      # @return [String] the title encoded into the generated PDF
      attribute :title
      # @return [String] "markdown" or "html"
      attribute :type
      # @return [Array<Hash>, Hash] the content to render
      attribute :data
      # @return [Hash] page size, margins and orientation
      attribute :page
      # @return [Hash] a logo to place on the page
      attribute :logo
      # @return [String] the filename to return the PDF under
      attribute :filename
    end
  end
end
