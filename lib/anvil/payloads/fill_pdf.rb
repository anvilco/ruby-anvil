# frozen_string_literal: true

module Anvil
  module Payloads
    # The body of a {Anvil::Client#fill_pdf} call.
    #
    # @see https://www.useanvil.com/docs/api/fill-pdf
    class FillPdf < Base
      # @return [String] the title encoded into the filled PDF
      attribute :title
      # @return [Numeric] the size of all filled text. The API defaults to 10
      attribute :font_size
      # @return [String] the color of all filled text, e.g. "#CC0000"
      attribute :text_color
      # @return [String] the font family of all filled text
      attribute :font_family
      # @return [Hash] the values to fill, keyed by the field ids on the PDF template
      attribute :data
    end
  end
end
