# frozen_string_literal: true

module Anvil
  module Payloads
    # The body of a {Anvil::Client#fill_pdf} call. Every field is generated from
    # the OpenAPI spec into {FillPdfRequest}; this is the name the client's API
    # uses for it.
    #
    # @see https://www.useanvil.com/docs/api/fill-pdf
    class FillPdf < FillPdfRequest
    end
  end
end
