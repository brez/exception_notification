require 'action_mailer'
require 'pp'

class ExceptionNotifier
  class Notifier < ActionMailer::Base
    self.mailer_name = 'exception_notifier'
    self.append_view_path "#{File.dirname(__FILE__)}/views"

    class << self
      def default_sender_address
        %("Exception Notifier" <exception.notifier@default.com>)
      end

      def default_exception_recipients
        []
      end

      def default_email_prefix
        "[ERROR] "
      end

      def default_sections
        %w(request session environment backtrace)
      end

      def default_options
        { :sender_address => default_sender_address,
          :exception_recipients => default_exception_recipients,
          :email_prefix => default_email_prefix,
          :sections => default_sections }
      end
    end

    class MissingController
      def method_missing(*args, &block)
      end
    end

    def exception_notification(env, exception)
      @env        = env
      @exception  = exception
      @options    = (env['exception_notifier.options'] || {}).reverse_merge(self.class.default_options)
      @kontroller = env['action_controller.instance'] || MissingController.new
      @request    = ActionDispatch::Request.new(env)
      @backtrace  = clean_backtrace(exception)
      @sections   = @options[:sections]
      data        = env['exception_notifier.exception_data'] || {}

      data.each do |name, value|
        instance_variable_set("@#{name}", value)
      end

      prefix   = "#{@options[:email_prefix]}#{@kontroller.controller_name}##{@kontroller.action_name}"
      subject  = "#{prefix} (#{@exception.class}) #{@exception.message.inspect}"

      unless full_throttle?
        mail(:to => @options[:exception_recipients], :from => @options[:sender_address], :subject => subject) do |format|
          format.text { render "#{mailer_name}/exception_notification" }
        end
      end

    end

    private

      def full_throttle?
        threshold_met?
      end

      def threshold_met?
        $exception_throttle_max ||= 0
        if $exception_throttle_max > 30
          $exception_throttle_max = 0 if an_hour_has_passed?
          return true
        end
        $exception_throttle_max += 1
        false
      end

      def an_hour_has_passed?
        $exception_time_stamp ||= Time.now
        if $exception_time_stamp < Time.now - 3600
          $exception_time_stamp = Time.now
          return true
        end
        false
      end

      def clean_backtrace(exception)
        Rails.respond_to?(:backtrace_cleaner) ?
          Rails.backtrace_cleaner.send(:filter, exception.backtrace) :
          exception.backtrace
      end

      helper_method :inspect_object

      def inspect_object(object)
        case object
        when Hash, Array
          object.inspect
        when ActionController::Base
          "#{object.controller_name}##{object.action_name}"
        else
          object.to_s
        end
      end
      
  end
end
