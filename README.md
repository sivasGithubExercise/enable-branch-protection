Adapted from [github-developer/using-the-github-api-in-your-app](https://github.com/github-developer/using-the-github-api-in-your-app).

This is an example GitHub App that automates the protection of the default branch upon creation of new repositories within a GitHub organization. This app will also protect the default_branch (Need to adjust the code if the default_brahcn is named other than 'master') of a specific GitHub organization upon installation.The creator of the new repository will be notified with an [@mention](https://help.github.com/en/articles/basic-writing-and-formatting-syntax#mentioning-people-and-teams) in an issue within the repository that outlines the protections that were added.

Scenarios Covered:
1. When this app is intalled on an organization, all existing unprotected repo's default branchs are enabled protection  (Need to adjust the code if the default_brahcn is named other than 'master')
1. When a new repo is created, that new repo default branches are protected
1. When a new file is pushed 


This project listens for [organization events](https://developer.github.com/webhooks/#events) and uses the [Octokit.rb](https://github.com/octokit/octokit.rb) library to make REST API calls.

## Prerequisites

To run this web service on your local machine, you will need to use a tool like Smee to send webhooks to your local machine without exposing it to the internet. 

### Start a new Smee channel

Go to <https://smee.io> and click **Start a new channel**.

Starting a new Smee channel creates a unique domain where GitHub can send webhook payloads. This domain is called a Webhook Proxy URL and looks something like this: `https://smee.io/Gos6hcCFQZindeoJ`

**Note:** The following steps are slightly different than the "Use the CLI" instructions you'll see on your Smee channel page. You do **not** need to follow the "Use the Node.js client" or "Using Probot's built-in support" instructions.

1. Install the Smee client

    ```sh
    npm install --global smee-client
    ```

1. Run the client (replacing `https://smee.io/Gos6hcCFQZindeoJ` with your own domain):

    ```sh
    smee --url https://smee.io/Gos6hcCFQZindeoJ --path /event_handler --port 3000
    ```

    You should see output like the following:

    ```sh
    Forwarding https://smee.io/Gos6hcCFQZindeoJ to http://127.0.0.1:3000/event_handler
    Connected https://smee.io/Gos6hcCFQZindeoJ
    ```

### Register a new GitHub App

Next, you will need to register a new GitHub App and install it in your GitHub organization.

1. Visit the settings page in your GitHub organization's profile, and click on GitHub Apps under Developer settings.
1. Click **New GitHub App**. You'll see a form where you can enter details about your app.
1. Give your app a name. This can be anything you'd like.
1. For the "Homepage URL", use the domain issued by Smee. For example: `https://smee.io/Gos6hcCFQZindeoJ`
1. For the "Webhook URL", again use the domain issued by Smee.
1. For the "Webhook secret", create a password to secure your webhook endpoints.


    Note this secret, you need to use this later for your config/env file.

1. Under Permissions, specify the following **Repository permissions** for your app:
    - **Administration** (Read & Write)
    - **Issues** (Read & Write)

1. Scroll down to **Subscribe to events** and make sure **Repository** is checked.

1. At the bottom of the page, specify whether this is a private app or a public app. For now, leave the app as private by selecting **Only on this account**.

1. Click **Create GitHub App** to create your app!

### Save your private key and App ID

After you create your app, you'll be taken back to the app settings page. You have two more things to do here:

1. **Generate a private key for your app**. This is necessary to authenticate your app later on. Scroll down on the page and click **Generate a private key**. Save the resulting PEM file in a directory where you can find it again.

1. **Note the app ID GitHub has assigned your app**. You'll need this later when you [set your environment variables](#Set-environment-variables).

### Install the app on your organization account

Now it's time to install the app. From your app's settings page, do the following:

1. Click **Install App** in the sidebar. Next to your organization name, click **Install**.

1. You'll be asked whether to install the app on all repositories or selected repositories. Select **All repositories**.

1. Click **Install**.

## Install

Run the following command to clone this repository:

```sh
git clone https://github.com/shivaraman10/enable-branch-protection.git
```

Install dependencies by running the following command from the project directory:

```sh
gem install bundler && bundle install
```

With the dependencies installed, you can [start the server](#Start-the-server).

## Set environment variables

1. Create a copy of the `.env-example` file called `.env`.

    ```sh
    cp .env-example .env
    ```

1. Add your GitHub App's private key, app ID, and webhook secret to the `.env` file.

    > **Note:** Copy the entire contents of your PEM file as the value of `GITHUB_PRIVATE_KEY` in your `.env` file.

    Because the PEM file is more than one line you'll need to add quotes around the value like the example below:

    ```pem
    PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----
    ...
    MIIEowIBAA...
    ...
    -----END RSA PRIVATE KEY-----"
    GITHUB_APP_IDENTIFIER=<<Your App Id>>
    GITHUB_WEBHOOK_SECRET=<<your-webhook-secret>>
    ```

## Start the server

1. Run `ruby server.rb` on the command line. You should see a response like:

    ```sh
    [2022-04-17 13:11:46] INFO  WEBrick 1.4.4
    [2022-04-17 13:11:46] INFO  ruby 2.6.8 (2021-07-07) [universal.arm64e-darwin21]
    == Sinatra (v2.0.4) has taken the stage on 3000 for development with backup from WEBrick
    [2022-04-17 13:11:46] INFO  WEBrick::HTTPServer#start: pid=25501 port=3000
    Use Ctrl-C to stop
    ```

1. View the Sinatra app at `localhost:3000` to verify your app is connected to the server.

The web service should now be running and watching for new repositories to be created within your organization! 🚀

When you create a new repository in your organization, you should see some output in the Terminal tab where you started `server.rb` that looks something like this:

```sh-session

```

This means your app is running on the server as expected. 🙌

If you don't see the output, make sure Smee is running correctly in another Terminal tab.

Also enhanced version of this server to handle App installation event and new repo/file creation event in `server_refined.rb`. You can run that using `ruby server_refined.rb` 

## Usage

You can add, remove, or modify the branch protection rules by changing the parameters inside the `options` array in the `protect_branch` helper method:

```ruby
def protect_branch(repo_name)
  #if the branch is not protected already then protect the branch
  if (@installation_client.branch_protection(repo_name, 'master').nil?)
    logger.debug "----enabling branch protection for the repo #{repo_name}"
    options = {
      # This header is necessary for beta access to the branch_protection API
      # See https://developer.github.com/v3/repos/branches/#update-branch-protection
      accept: 'application/vnd.github.luke-cage-preview+json',
      # Require at least two approving reviews on a pull request before merging
      required_pull_request_reviews: { required_approving_review_count: 2 },
      # Enforce all configured restrictions for administrators
      enforce_admins: true
    }
    @installation_client.protect_branch(repo_name, 'master', options)
  end
end
```

You can find a list of branch protection parameters in the [GitHub Developer Guide](https://developer.github.com/v3/repos/branches/#update-branch-protection).

If you change any of the branch protection parameters in the `protect_default_branch` helper method, you should update the  `issue_body` variable in the `notify_user` helper method to reflect those changes:

```ruby
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
```

## Troubleshooting

If you run into any problems, check out the Troubleshooting section in the "[Setting up your development environment](https://developer.github.com/apps/quickstart-guides/setting-up-your-development-environment/#troubleshooting)" quickstart guide on [developer.github.com](developer.github.com). If you run into any other trouble, you can [open an issue](https://github.com/parkerbxyz/default-branch-protector/issues/new) in this repository.

## Resources

- [Setting up your development environment | GitHub Developer Guide](https://developer.github.com/apps/quickstart-guides/setting-up-your-development-environment/)
- [Using the GitHub API in your app | GitHub Developer Guide](https://developer.github.com/apps/quickstart-guides/using-the-github-api-in-your-app/)
- [Branches | GitHub Developer Guide](https://developer.github.com/v3/repos/branches/#update-branch-protection)
- [github-developer/using-the-github-api-in-your-app](https://github.com/github-developer/using-the-github-api-in-your-app)
- [Using the Octokit library API in your app | Octokit Developer Guide](https://octokit.github.io/octokit.rb/Octokit/Client/Repositories.html#all_repositories-instance_method)
- [Using the Octokit library API in your app | Octokit Client library](https://octokit.github.io/octokit.rb/Octokit/Client.html)
