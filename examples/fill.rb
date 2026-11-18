# Fill a PDF template with JSON data and write the result.
# Docs: https://www.useanvil.com/docs/api/fill-pdf
#
#   ANVIL_API_KEY=yourKey ruby fill.rb

require "anvil"

# A sample PDF template available to any account. See
# https://www.useanvil.com/help/tutorials/set-up-a-pdf-template to set up your own
PDF_TEMPLATE_ID = "05xXsZko33JIO6aq5Pnr"

client = Anvil::Client.new(api_key: ENV.fetch("ANVIL_API_KEY"))

response = client.fill_pdf(PDF_TEMPLATE_ID, {
                             title: "Filled by ruby-anvil",
                             fontSize: 10,
                             textColor: "#333333",
                             data: { name: "Sally Jones", email: "sally@example.com" }
                           })

File.binwrite("fill.output.pdf", response.data)
puts "Wrote fill.output.pdf (#{response.data.bytesize} bytes)"
