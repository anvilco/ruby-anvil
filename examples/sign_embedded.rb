# Embedded e-signing: create a packet whose signer signs inside your own app,
# get the URL to show them, check on the packet, and download its documents.
# Docs: https://www.useanvil.com/docs/api/e-signatures
#
#   ANVIL_API_KEY=yourKey bundle exec ruby examples/sign_embedded.rb your.real.email@example.com
#
# From a clone, run it from the repository root as above. With the gem
# installed, plain `ruby sign_embedded.rb your.real.email@example.com` works too.
#
# Embedded signers are not emailed. The packet appears in your dashboard's
# e-sign area, and you show the signing URL yourself.

require "anvil"

# A sample PDF template available to any account. See
# https://www.useanvil.com/help/tutorials/set-up-a-pdf-template to set up your own
PDF_TEMPLATE_ID = "05xXsZko33JIO6aq5Pnr"

signer_email = ARGV[0]
abort "Pass your email address as the first argument" if signer_email.nil? || signer_email.empty?

client = Anvil::Client.new(api_key: ENV.fetch("ANVIL_API_KEY"))

# 1. Create the packet, with a signer who will sign in your app
packet = client.create_etch_packet(
  variables: Anvil::Payloads::CreateEtchPacket.new(
    name: "Embedded signing - Testy Signer",
    is_draft: false,
    # Test packets use development signatures and are not billed
    is_test: true,

    files: [
      Anvil::Payloads::EtchFile.new(id: "sampleTemplate", cast_eid: PDF_TEMPLATE_ID)
    ],

    data: { payloads: { sampleTemplate: { data: { name: "Testy Signer", email: signer_email } } } },

    signers: [
      Anvil::Payloads::EtchSigner.new(
        id: "signer1",
        name: "Testy Signer",
        email: signer_email,
        # An embedded signer signs through a URL you show them, rather than
        # one emailed to them
        signer_type: "embedded",
        fields: [Anvil::Payloads::SignerField.new(file_id: "sampleTemplate", field_id: "signature")]
      )
    ]
  )
)

puts "Created packet #{packet.eid}"

# 2. Get the URL for the signer. Show it in an iframe, or redirect to it
sign_url = client.generate_etch_sign_url(
  signer_eid: packet.signers.first.eid,
  # Your own id for the person signing
  client_user_id: "user-123"
)

puts "Send the signer to: #{sign_url}"

# 3. Check on the packet, once your app is told signing is done. A webhook can
# tell you instead: https://www.useanvil.com/docs/api/webhooks
status = client.get_etch_packet(eid: packet.eid)
puts "Packet status: #{status.status}, signers remaining: #{status.number_remaining_signers}"

# 4. Download the documents as a zip. Once everyone has signed, these are the
# signed versions. Streamed to the file rather than held in memory
File.open("documents.zip", "wb") do |file|
  client.download_documents(packet.document_group.eid, data_type: :stream, to: file)
end

puts "Documents saved to documents.zip"
