require 'sinatra'
require 'octokit'
require 'dotenv/load' # Manages environment variables
require 'json'
require 'openssl'     # Verifies the webhook signature
require 'jwt'         # Authenticates a GitHub App
require 'time'        # Gets ISO 8601 representation of a Time object
require 'logger'      # Logs debug statements

set :port, 3000
set :bind, '0.0.0.0'


# This is template code to create a GitHub App server.
# You can read more about GitHub Apps here: # https://developer.github.com/apps/
#
# On its own, this app does absolutely nothing, except that it can be installed.
# It's up to you to add functionality!
# You can check out one example in advanced_server.rb.
#
# This code is a Sinatra app, for two reasons:
#   1. Because the app will require a landing page for installation.
#   2. To easily handle webhook events.
#
# Of course, not all apps need to receive and process events!
# Feel free to rip out the event handling code if you don't need it.
#
# Have fun!
#

class GHApp < Sinatra::Application

  # Expects that the private key in PEM format. Converts the newlines
  PRIVATE_KEY = OpenSSL::PKey::RSA.new(ENV['GITHUB_PRIVATE_KEY'].gsub('\n', "\n"))

  # Your registered app must have a secret set. The secret is used to verify
  # that webhooks are sent by GitHub.
  WEBHOOK_SECRET = ENV['GITHUB_WEBHOOK_SECRET']

  # The GitHub App's identifier (type integer) set when registering an app.
  APP_IDENTIFIER = ENV['GITHUB_APP_IDENTIFIER']

  # Turn on Sinatra's verbose logging during development
  configure :development do
    set :logging, Logger::DEBUG
  end


  # Before each request to the `/event_handler` route
  before '/event_handler' do
    get_payload_request(request)
    verify_webhook_signature
    authenticate_app
    # Authenticate the app installation in order to run API operations
    authenticate_installation(@payload)
  end


  post '/event_handler' do
   #Get the GitHub WebHook event to process requried events 
    case request.env['HTTP_X_GITHUB_EVENT']
      #When a pull requst is created for a new file push
      when 'pull_request'
        if @payload['action'].match?('opened')
          enable_branch_protection(@payload)
          notify_user(@payload)
        end
      #Handles when a new repo is created in the given organiztaion  
      when 'repository'
        if @payload['action'].match?('created')
          enable_branch_protection(@payload)
          notify_user(@payload)
        end
      #Handles all the repos in the current organization when this app is installed.
      when 'installation'
        if @payload['action'].match?('created')
          enable_branch_protection(@payload)
          notify_user(@payload)
        end         
    end

    200 # success status
  end


  helpers do
    
    # Open an issue to notify the user of branch protection rules
    def notify_user(payload)
      username = payload['sender']['login']
      help_url = 'https://help.github.com/en/articles/about-protected-branches'
      issue_title = 'Default Branch Protected 🔐'
      issue_body = <<~BODY
        @#{username}: branch protection rules have been added to the Master branch.
        - Collaborators cannot force push to the protected branch or delete the branch
        - All commits must be made to a non-protected branch and submitted via a pull request
        - There must be least 2 approving reviews and no changes requested before a PR can be merged
        \n **Note:** All configured restrictions are enforced for administrators.
        \n You can learn more about protected branches here: [About protected branches - GitHub Help](#{help_url})
      BODY
      logger.debug 'Creating a new issue for automatic branch protection'
      @installation_client.create_issue(@repo, issue_title, issue_body)
    end
    
    # Protects the master branch ( assumption made here as we will not get the default branch name in the payload for installation event) 
    def protect_branch(repo_name, master_branch)
      #if the branch is not protected already then protect the branch
      if (@installation_client.branch_protection(repo_name, master_branch).nil?)
        logger.debug "----enabling branch protection for the repo #{repo_name}"
        options = {
          # This header is necessary for beta access to the branch_protection API
          # See https://developer.github.com/v3/repos/branches/#update-branch-protection
          accept: 'application/vnd.github.luke-cage-preview+json',
          # Require at least two approving reviews on a pull request before merging
          required_pull_request_reviews: { required_approving_review_count: 1 },
          # Enforce all configured restrictions for administrators
          enforce_admins: true
        }
        @installation_client.protect_branch(repo_name, master_branch, options)
      end
    end

    # Handles when an app is installed in an org, or a repo is created or a pull request is created
    # Invokes protect_branch method to protect master branch 
    def enable_branch_protection(payload)
      # Get the list of repos for this org. When App is installed
      if(!@payload['repositories'].nil?)     
        repos = @payload['repositories']
        for repo_name in repos
          logger.debug "----    repos #{repo_name['full_name']}"
          protect_branch(repo_name['full_name'],'master') unless repo_name['private'] == true
        end
      else
        @repo = payload['repository']['full_name']  # When a new repo or a pull_request is created
        @branch = payload['repository']['default_branch']  # When a new repo or a pull_request is created
        # Sleep for half a sec, in case if default branch creation is delayed for some reason
        sleep(0.5) 
        # Protect the default branch if its not a private repo
        protect_branch(@repo,@branch) unless payload['repository']['private'] == true
      end  
    end

    # Saves the raw payload and converts the payload to JSON format
    def get_payload_request(request)
      # request.body is an IO or StringIO object
      # Rewind in case someone already read it
      request.body.rewind
      # The raw text of the body is required for webhook signature verification
      @payload_raw = request.body.read
      #logger.debug "---- received #{@payload_raw}"
      begin
        @payload = JSON.parse @payload_raw
        #logger.debug "---- received #{@payload}"
      rescue => e
        fail  "Invalid JSON (#{e}): #{@payload_raw}"
      end
    end

    # Instantiate an Octokit client authenticated as a GitHub App.
    # GitHub App authentication requires that you construct a
    # JWT (https://jwt.io/introduction/) signed with the app's private key,
    # so GitHub can be sure that it came from the app and wasn't alterered by
    # a malicious third party.
    def authenticate_app
      payload = {
          # The time that this JWT was issued, _i.e._ now.
          iat: Time.now.to_i,

          # JWT expiration time (10 minute maximum)
          exp: Time.now.to_i + (10 * 60),

          # Your GitHub App's identifier number
          iss: APP_IDENTIFIER
      }

      # Cryptographically sign the JWT.
      jwt = JWT.encode(payload, PRIVATE_KEY, 'RS256')

      # Create the Octokit client, using the JWT as the auth token.
      @app_client ||= Octokit::Client.new(bearer_token: jwt)
    end

    # Instantiate an Octokit client, authenticated as an installation of a
    # GitHub App, to run API operations.
    def authenticate_installation(payload)
      @installation_id = payload['installation']['id']
      @installation_token = @app_client.create_app_installation_access_token(@installation_id)[:token]
      @installation_client = Octokit::Client.new(bearer_token: @installation_token)
    end

    # Check X-Hub-Signature to confirm that this webhook was generated by
    # GitHub, and not a malicious third party.
    #
    # GitHub uses the WEBHOOK_SECRET, registered to the GitHub App, to
    # create the hash signature sent in the `X-HUB-Signature` header of each
    # webhook. This code computes the expected hash signature and compares it to
    # the signature sent in the `X-HUB-Signature` header. If they don't match,
    # this request is an attack, and you should reject it. GitHub uses the HMAC
    # hexdigest to compute the signature. The `X-HUB-Signature` looks something
    # like this: "sha1=123456".
    # See https://developer.github.com/webhooks/securing/ for details.
    def verify_webhook_signature
      their_signature_header = request.env['HTTP_X_HUB_SIGNATURE'] || 'sha1='
      method, their_digest = their_signature_header.split('=')
      our_digest = OpenSSL::HMAC.hexdigest(method, WEBHOOK_SECRET, @payload_raw)
      halt 401 unless their_digest == our_digest

      # The X-GITHUB-EVENT header provides the name of the event.
      # The action value indicates the which action triggered the event.
      logger.debug "---- received event #{request.env['HTTP_X_GITHUB_EVENT']}"
      logger.debug "----    action #{@payload['action']}" unless @payload['action'].nil?
    end
  end

  # Finally some logic to let us run this server directly from the command line,
  # or with Rack. Don't worry too much about this code. But, for the curious:
  # $0 is the executed file
  # __FILE__ is the current file
  # If they are the same—that is, we are running this file directly, call the
  # Sinatra run method
  run! if __FILE__ == $0
end
