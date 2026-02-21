module FizzyPop
  class Agent
    attr_reader :name, :accounts

    def initialize(name:, token:, base_url:, interval_agent_poll: 0.5)
      @name = name
      @client = FizzyClient.new(base_url, token)
      @interval_agent_poll = interval_agent_poll
      @accounts = nil
    end

    def fetch_identity!
      Debug.breadcrumbs << "get_identity:#{@name}"
      puts "\e[33m[#{@name}]\e[0m Fetching identity..."
      identity = @client.identity

      if identity
        @accounts = identity["accounts"]
        @user_id = @accounts&.first&.dig("user", "id")
        puts "\e[32m[#{@name}]\e[0m Found #{@accounts&.length || 0} account(s) (user: #{@user_id})"
      else
        puts "\e[31m[#{@name}]\e[0m Failed to fetch identity"
        @accounts = []
      end

      self
    end

    def active?
      @accounts && !@accounts.empty?
    end

    def user_id
      @user_id
    end

    def poll_notifications(queue, bot_user_ids: [])
      @accounts.each do |account|
        slug = account["slug"]

        Debug.breadcrumbs << "get_notifications:#{@name}"
        notifications = @client.notifications(slug)
        next unless notifications

        unread = notifications.select { |n| !n["read"] }.first

        if unread.nil?
          next
        elsif Debug.dry_run
          puts "\e[33m[#{@name}]\e[0m Will mark notification #{unread["id"]} as read."
        else
          Debug.breadcrumbs << "read_notification:#{@name}"
          @client.mark_read(slug, unread["id"])
          puts "\e[33m[#{@name}]\e[0m Marked notification #{unread["id"]} as read."
        end

        next if unread["creator"].nil?

        # Skip notifications from other bot agents to avoid bot-to-bot noise,
        # UNLESS the notification body explicitly @mentions this agent by name.
        creator_id = unread["creator"]["id"]
        if bot_user_ids.include?(creator_id)
          body_text = unread["body"].to_s.downcase
          agent_mentioned = body_text.include?("@#{@name.downcase}")
          unless agent_mentioned
            puts "\e[90m[#{@name}]\e[0m Skipping notification from bot agent #{unread["creator"]["name"]} (#{creator_id})"
            next
          end
          puts "\e[33m[#{@name}]\e[0m Bot agent #{unread["creator"]["name"]} mentioned @#{@name} — delivering anyway."
        end

        message = <<~PROMPT
                  You have a new notification in Fizzy that requires your attention.

                  # Fizzy command check
                  DO NOTHING if fizzy is not available in shell.

                  # Task
                  - Read the Card from the notification.
                  - Read the latest comment on the card.
                  - Check whether the card already have 👀 reaction (boost) from you.
                    - Send 👀 boost to the card URL provided ONLY WHEN there is no boost from you
                  - DO THE INSTRUCTION in the latest comment if any instruction is provided.
                  - DO NOTHING if there is no action.

                  # Notification details
                  From: #{unread["creator"]["name"]} (#{unread["creator"]["id"]})
                  Title: #{unread["title"]}
                  Message: #{unread["body"]}
                  Card: #{unread["card"]["url"].split("/").last}

                  # Commands Reference
                  fizzy reaction list --card NUMBER
                  fizzy reaction create --card NUMBER --content "emoji"
                  fizzy reaction delete REACTION_ID --card NUMBER
                  fizzy reaction list --card NUMBER --comment COMMENT_ID
                  fizzy reaction create --card NUMBER --comment COMMENT_ID --content "emoji"
                  fizzy reaction delete REACTION_ID --card NUMBER --comment COMMENT_ID
                  fizzy comment list --card NUMBER [--page N] [--all]
                  fizzy comment show COMMENT_ID --card NUMBER
                  fizzy comment create --card NUMBER --body "HTML" [--body_file PATH] [--created-at TIMESTAMP]
                  fizzy comment update COMMENT_ID --card NUMBER [--body "HTML"] [--body_file PATH]
                  fizzy comment delete COMMENT_ID --card NUMBER
                  fizzy card column CARD_NUMBER --column ID     # Move to column (use column ID or: maybe, not-yet, done)
                  fizzy card move CARD_NUMBER --to BOARD_ID     # Move card to a different board
                  fizzy card assign CARD_NUMBER --user ID       # Toggle user assignment
                  fizzy card tag CARD_NUMBER --tag "name"       # Toggle tag (creates tag if needed)
                  fizzy card watch CARD_NUMBER                  # Subscribe to notifications
                  fizzy card unwatch CARD_NUMBER                # Unsubscribe
                  fizzy card pin CARD_NUMBER                    # Pin card for quick access
                  fizzy card unpin CARD_NUMBER                  # Unpin card
                  fizzy card golden CARD_NUMBER                 # Mark as golden/starred
                  fizzy card ungolden CARD_NUMBER               # Remove golden status
                  fizzy card image-remove CARD_NUMBER           # Remove header image
                PROMPT

        puts "\e[33m[#{@name}]\e[0m #{message}"

        queue << { agent_name: @name, message: message }
      end

      sleep @interval_agent_poll
    end
  end
end
