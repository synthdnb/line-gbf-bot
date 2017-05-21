#!/usr/bin/env ruby
require 'rubygems'
require 'bundler/setup'

require 'sinatra'
require 'line/bot'
require 'pry'
require 'redis'

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

set :bind, "0.0.0.0"

def redis
  @redis ||= Redis.new(host: "redis")
end

def client
  @client ||= Line::Bot::Client.new { |config|
    config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
    config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
  }
end

def get_display_name user_id
  response = client.get_profile(user_id)
  case response
  when Net::HTTPSuccess then
    contact = JSON.parse(response.body)
    contact['displayName']
  else
    nil
  end
end


reserved = %w(공지 등록 삭제 목록)

post '/callback' do
  body = request.body.read

  signature = request.env['HTTP_X_LINE_SIGNATURE']
  unless client.validate_signature(body, signature)
    error 400 do 'Bad Request' end
  end

  events = client.parse_events_from(body)
  events.each { |event|
    p event
    case event
    when Line::Bot::Event::Follow
      message = {
        type: 'text',
        text: "기공단 봇입니다. 공지 등을 개인 메시지로 보내줍니다."
      }
      client.reply_message(event['replyToken'], message)
      user_id = event["source"]["userId"]
      redis.sadd "receivers", user_id
      puts "Follow from #{user_id}"
    when Line::Bot::Event::Unfollow
      user_id = event["source"]["userId"]
      redis.srem "receivers", user_id
      puts "UnFollow from #{user_id}"
    when Line::Bot::Event::Message
      case event.type
      when Line::Bot::Event::MessageType::Text
        if event.message['text'].match(/\A!(\S+)(.*)/m)
          cmd = $1
          content = $2.strip
          message = {}
          keywords = redis.hkeys "keywords"
          case cmd
          when "공지"
            break unless event["source"]["type"] == "user"
            sender = get_display_name(event["source"]["userId"])
            message = {
              type: 'text',
              text: "[기공단 공지사항] From #{sender}\n#{content}"
            }
            receivers = redis.smembers "receivers" 
            receivers.each do |target|
              client.push_message target, message
            end
            message = {
              type: 'text',
              text: "#{receivers.length}명에게 공지를 발송했습니다"
            }
            client.reply_message(event['replyToken'], message)
          when "등록"
            break unless event["source"]["type"] == "user"
            content.match /\A(\S+)(.*)/m
            key = $1
            value = $2.strip
            if reserved.include? key
              message = {
                type: 'text',
                text: "예약된 키워드입니다",
              }
            else
              redis.hset "keywords", key, value
              message = {
                type: 'text',
                text: "키워드 '#{key}' 등록을 완료했습니다",
              }
            end
            client.reply_message(event['replyToken'], message)
          when "삭제"
            break unless event["source"]["type"] == "user"
            content.match /\A(\S+)(.*)/m
            key = $1
            redis.hdel "keywords", key
            message = {
              type: 'text',
              text: "키워드 '#{key}' 삭제를 완료했습니다",
            }
            client.reply_message(event['replyToken'], message)
          when "목록"
            break unless event["source"]["type"] == "user"
            message = {
              type: 'text',
              text: "키워드 목록: #{keywords.join(", ")}",
            }
            client.reply_message(event['replyToken'], message)
          when *keywords
            response = redis.hget "keywords", cmd
            message = {
              type: 'text',
              text: response
            }
            client.reply_message(event['replyToken'], message)
          else
            break unless event["source"]["type"] == "user"
            message = {
              type: 'text',
              text: "알 수 없는 명령입니다",
            }
            client.reply_message(event['replyToken'], message)
          end
        end
      when Line::Bot::Event::MessageType::Image, Line::Bot::Event::MessageType::Video
        # response = client.get_message_content(event.message['id'])
        # tf = Tempfile.open("content")
        # tf.write(response.body)
      end
    end
  }
  "OK"
end
