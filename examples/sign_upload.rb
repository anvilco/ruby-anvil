# Create an Etch e-sign packet from your own PDF: upload the file, place the
# fields on it, and send it to a signer.
# Docs: https://www.useanvil.com/docs/api/e-signatures#uploading-a-new-pdf
#
#   ANVIL_API_KEY=yourKey bundle exec ruby examples/sign_upload.rb your.real.email@example.com /path/to/file.pdf
#
# From a clone, run it from the repository root as above. With the gem
# installed, plain `ruby sign_upload.rb your.real.email@example.com file.pdf`
# works too.
#
# A signature request email goes to the address you pass, so use a real one.

require "anvil"

signer_email, pdf_path = ARGV
if signer_email.nil? || signer_email.empty? || pdf_path.nil? || pdf_path.empty?
  abort "Pass your email address and a PDF: ruby examples/sign_upload.rb you@example.com file.pdf"
end

client = Anvil::Client.new(api_key: ENV.fetch("ANVIL_API_KEY"))

# Wraps the file for upload. It also takes an IO or a StringIO; pass
# `filename:` and `mimetype:` when they can't be worked out from the input.
# The file is streamed to the API rather than read into memory
upload = Anvil.prepare_graphql_file(pdf_path)

packet = client.create_etch_packet(
  variables: Anvil::Payloads::CreateEtchPacket.new(
    name: "Uploaded PDF - Testy Signer",
    # The packet is ready to send: an email goes to the signer. Use
    # is_draft: true to review it in the dashboard first
    is_draft: false,
    # Test packets use development signatures and are not billed
    is_test: true,
    signature_email_subject: "Please sign this document",

    files: [
      Anvil::Payloads::EtchFile.new(
        # Your own id, for referencing this file in `signers` below
        id: "uploadedPdf",
        title: "Please sign this document",
        file: upload,

        # Where each field sits on the uploaded PDF, in points from the
        # top-left of the page. Set up a template in the dashboard instead
        # to place fields visually
        fields: [
          { id: "signature1", type: "signature", pageNum: 0,
            rect: { x: 400, y: 100, width: 150, height: 30 } },
          { id: "signatureDate1", type: "signatureDate", pageNum: 0,
            rect: { x: 400, y: 140, width: 150, height: 30 } }
        ]
      )
    ],

    signers: [
      Anvil::Payloads::EtchSigner.new(
        id: "signer1",
        name: "Testy Signer",
        email: signer_email,
        signer_type: "email",
        # The fields this signer clicks through, in this order
        fields: [
          Anvil::Payloads::SignerField.new(file_id: "uploadedPdf", field_id: "signature1"),
          Anvil::Payloads::SignerField.new(file_id: "uploadedPdf", field_id: "signatureDate1")
        ]
      )
    ]
  )
)

puts "Created packet #{packet.eid} from #{pdf_path}"
puts "Visit it on your dashboard: #{packet.details_url}"
puts "A signature request was emailed to #{signer_email}"
