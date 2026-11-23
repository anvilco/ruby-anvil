# Create an Etch e-sign packet and send it to a signer.
# Docs: https://www.useanvil.com/docs/api/e-signatures
#
#   ANVIL_API_KEY=yourKey bundle exec ruby examples/sign.rb your.real.email@example.com
#
# From a clone, run it from the repository root as above. With the gem
# installed, `ruby sign.rb your.real.email@example.com` works anywhere.
#
# A signature request email goes to the address you pass, so use a real one.

require "anvil"

PDF_TEMPLATE_ID = "05xXsZko33JIO6aq5Pnr"

signer_email = ARGV[0]
abort "Pass your email address as the first argument" if signer_email.nil? || signer_email.empty?

client = Anvil::Client.new(api_key: ENV.fetch("ANVIL_API_KEY"))

packet = client.create_etch_packet(
  variables: Anvil::Payloads::CreateEtchPacket.new(
    name: "Test Docs - Testy Signer",
    # Ready to send: an email goes to the first signer. Use is_draft: true to
    # review it in the dashboard first
    is_draft: false,
    # Test packets use development signatures and are not billed
    is_test: true,
    signature_email_subject: "Please sign these documents",

    files: [
      Anvil::Payloads::EtchFile.new(id: "sampleTemplate", cast_eid: PDF_TEMPLATE_ID)
    ],

    # Fills the PDF before it goes out for signature
    data: { payloads: { sampleTemplate: { data: { name: "Testy Signer", email: signer_email } } } },

    signers: [
      Anvil::Payloads::EtchSigner.new(
        id: "signer1",
        name: "Testy Signer",
        email: signer_email,
        signer_type: "email",
        fields: [Anvil::Payloads::SignerField.new(file_id: "sampleTemplate", field_id: "signature")]
      )
    ]
  )
)

puts "Visit the new packet on your dashboard: #{packet.details_url}"
