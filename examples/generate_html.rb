# Generate a PDF from HTML and CSS. Nothing needs setting up in the dashboard.
# Docs: https://www.useanvil.com/docs/api/generate-pdf#html--css-to-pdf
#
#   ANVIL_API_KEY=yourKey ruby generate_html.rb

require "anvil"

client = Anvil::Client.new(api_key: ENV.fetch("ANVIL_API_KEY"))

response = client.generate_pdf(
  title: "Example Invoice",
  type: "html",
  data: {
    html: <<~HTML,
      <h1 class="header-one">What is Lorem Ipsum?</h1>
      <p>Lorem Ipsum is simply dummy text of the printing industry.</p>
      <h3 class="header-two">Where does it come from?</h3>
      <p>Contrary to popular belief, Lorem Ipsum is not simply <i>random text</i>.</p>
    HTML
    css: <<~CSS
      body { font-size: 14px; color: #171717; }
      .header-one { text-decoration: underline; }
      .header-two { font-style: italic; }
    CSS
  }
)

File.binwrite("generate.output.pdf", response.data)
puts "Wrote generate.output.pdf (#{response.data.bytesize} bytes)"
