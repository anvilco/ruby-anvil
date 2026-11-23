# Generate a PDF from markdown content blocks.
# Docs: https://www.useanvil.com/docs/api/generate-pdf#markdown-to-pdf
#
#   ANVIL_API_KEY=yourKey bundle exec ruby examples/generate_markdown.rb
#
# From a clone, run it from the repository root as above. With the gem
# installed, plain `ruby generate_markdown.rb` works too.

require "anvil"

client = Anvil::Client.new(api_key: ENV.fetch("ANVIL_API_KEY"))

response = client.generate_pdf(
  title: "Example Invoice",
  data: [
    { label: "Name", content: "Sally Jones" },
    { content: "Lorem **ipsum** dolor sit _amet_" },
    {
      table: {
        firstRowHeaders: true,
        rows: [
          ["Description", "Quantity", "Price"],
          ["4x Large Widgets", "4", "$40.00"],
          ["10x Medium Widgets", "10", "$100.00"]
        ]
      }
    }
  ]
)

File.binwrite("generate.output.pdf", response.data)
puts "Wrote generate.output.pdf (#{response.data.bytesize} bytes)"
