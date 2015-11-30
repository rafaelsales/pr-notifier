require 'octokit'
require 'slack-ruby-client'

class PrNotifier
  def call(env)
    threshold = env.GET['threshold']
    repo = env.GET['repo']
    slack_room = env.GET['slack_room']

    old_prs = Github.new.old_pull_requests(repo, threshold)

    SlackNotifier.new.notify_old_prs(repo, old_prs) if old_prs.length > 0

    [200, {}, nil]
  rescue => e
    [500, {}, e.message]
  end
end

class Github
  def old_pull_requests(repo, threshold_hours)
    prs = Octokit.pull_requests(repo)
    prs.select do |pr|
      pr.updated_at < (Time.now - threshold_in_seconds(threshold_hours))
    end
  end

  private

  def threshold_in_seconds(threshold)
    threshold * 60 * 60
  end
end

class SlackNotifier
  def notify_old_prs(prs, channel_name)
    channel = find_channel(channel_name)

    client.chat_postMessage(channel: channel['id'],
                            text: formatted_message(prs),
                            as_user: true)
  end

  private

  def formatted_message(prs)
    prs_messages = prs.inject([]) do |pr, array|
      array << "#{pr['title']} last update was #{pr['updated_at']}"
    end

    "There are some old pull-requests that need review\n #{prs_messages.join('\n')}"
  end

  def find_channel(channel_name)
    client.channel_list['channels'].find do |c|
      c['name'] == channel_name
    end
  end

  def client
    @client ||= Slack::Web::Client.new { |c| c.auth_test }
  end
end
