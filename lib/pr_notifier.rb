require 'octokit'
require 'slack-ruby-client'
require 'byebug'
require 'rack/request'

class PrNotifier
  def call(env)
    req = Rack::Request.new(env)

    threshold = req.GET.fetch('threshold', '24').to_i
    repo = req.GET.fetch('repo', 'heartbits/capistrano-db_sync')
    slack_room = req.GET.fetch('slack_room', 'notifications')
    slack_token = req.GET.fetch('slack_token', '')
    github_token = req.GET.fetch('github_token', '')

    old_prs = Github.new(github_token).old_pull_requests(repo, threshold)

    # Working until this line
    if old_prs.length > 0
      SlackNotifier.new(slack_token).notify_old_prs(repo, old_prs, threshold)
    end

    [200, {}, nil]
  rescue => e
    [500, {}, e.message]
  end
end

class Github
  def initialize(access_token)
    self.access_token = access_token
  end

  def old_pull_requests(repo, threshold_hours)
    prs = client.pull_requests(repo)
    prs.select do |pr|
      comments_are_old?(repo, pr, threshold_hours)
    end
  end

  def comments_are_old?(repo, pr, threshold_hours)
    client.issue_comments(repo, pr.number).all? do |comment|
      comment.updated_at < (Time.now - threshold_in_seconds(threshold_hours))
    end
  end

  private

  attr_accessor :access_token

  def threshold_in_seconds(threshold)
    threshold * 60 * 60
  end

  def client
    @client ||= Octokit::Client.new(access_token: access_token)
  end
end

class SlackNotifier
  def initialize(access_token)
    self.access_token = access_token
  end

  def notify_old_prs(prs, channel_name, threshold_hours)
    channel = find_channel(channel_name)

    client.chat_postMessage(channel: channel['id'],
                            text: formatted_message(prs, threshold_hours),
                            as_user: true)
  end

  private

  attr_accessor :access_token

  def formatted_message(prs, threshold_hours)
    prs_messages = prs.inject([]) do |pr, array|
      array << "* ##{pr.number} - #{pr.title}"
    end

    headline = "There are PRs without comments for more than #{threshold_hours} hours:\n"
    headline + prs_messages.join("\n")
  end

  def find_channel(channel_name)
    client.channel_list['channels'].find do |c|
      c['name'] == channel_name
    end
  end

  def client
    @client ||= Slack::Web::Client.new(token: access_token).tap { |c| c.auth_test }
  end
end
