require 'forwardable'
require 'socket'
require 'selenium-webdriver'

module Applitools::Selenium
  class Driver < SimpleDelegator
    extend Forwardable

    include Selenium::WebDriver::DriverExtensions::HasInputDevices

    RIGHT_ANGLE = 90.freeze
    ANDROID = 'ANDROID'.freeze
    IOS = 'IOS'.freeze
    LANDSCAPE = 'LANDSCAPE'.freeze

    IE = 'ie'.freeze
    FIREFOX = 'firefox'.freeze

    FINDERS = {
      class: 'class name',
      class_name: 'class name',
      css: 'css selector',
      id: 'id',
      link: 'link text',
      link_text: 'link text',
      name: 'name',
      partial_link_text: 'partial link text',
      tag_name: 'tag name',
      xpath: 'xpath'
    }.freeze

    JS_GET_USER_AGENT = 'return navigator.userAgent;'.freeze

    def_delegators :@eyes, :user_inputs, :clear_user_inputs

    # If driver is not provided, Applitools::Selenium::Driver will raise an EyesError exception.
    def initialize(eyes, options)
      super(options[:driver])

      @is_mobile_device = options.fetch(:is_mobile_device, false)
      @eyes = eyes

      raise 'Incapable of taking screenshots!' unless capabilities.takes_screenshot?
    end

    # Rotates the image as necessary. The rotation is either manually forced by passing a value in
    # the +rotation+ parameter, or automatically inferred if the +rotation+ parameter is +nil+.
    #
    # +driver+:: +Applitools::Selenium::Driver+ The driver which produced the screenshot.
    # +image+:: +ChunkyPNG::Canvas+ The image to normalize.
    # +rotation+:: +Integer+|+nil+ The degrees by which to rotate the image: positive values = clockwise rotation,
    #   negative values = counter-clockwise, 0 = force no rotation, +nil+ = rotate automatically when needed.
    def self.normalize_rotation(driver, image, rotation)
      return if rotation == 0

      num_quadrants = 0
      if !rotation.nil?
        if rotation % RIGHT_ANGLE != 0
          raise Applitools::EyesError.new('Currently only quadrant rotations are supported. Current rotation: '\
            "#{rotation}")
        end
        num_quadrants = (rotation / RIGHT_ANGLE).to_i
      elsif rotation.nil? && driver.mobile_device? && driver.landscape_orientation? && image.height > image.width
        # For Android, we need to rotate images to the right, and for iOS to the left.
        num_quadrants = driver.android? ? 1 : -1
      end

      Applitools::Utils::ImageUtils.quadrant_rotate!(image, num_quadrants)
    end

    # Returns:
    # +String+ The platform name or +nil+ if it is undefined.
    def platform_name
      capabilities['platformName']
    end

    # Returns:
    # +String+ The platform version or +nil+ if it is undefined.
    def platform_version
      version = capabilities['platformVersion']
      version.nil? ? nil : version.to_s
    end

    # Returns:
    # +true+ if the driver is an Android driver.
    def android?
      platform_name.to_s.upcase == ANDROID
    end

    # Returns:
    # +true+ if the driver is an iOS driver.
    def ios?
      platform_name.to_s.upcase == IOS
    end

    # Returns:
    # +true+ if the driver orientation is landscape.
    def landscape_orientation?
      driver.orientation.to_s.upcase == LANDSCAPE
    rescue NameError
      Applitools::EyesLogger.debug 'driver has no "orientation" attribute. Assuming: portrait.'
    end

    # Returns:
    # +true+ if the platform running the test is a mobile platform. +false+ otherwise.
    def mobile_device?
      # We CAN'T check if the device is an +Appium::Driver+ since it is not a RemoteWebDriver. Because of that we use a
      # flag we got as an option in the constructor.
      @is_mobile_device
    end

    # Return a PNG screenshot in the given format as a string
    #
    # +output_type+:: +Symbol+ The format of the screenshot. Accepted values are +:base64+ and +:png+.
    # +rotation+:: +Integer+|+nil+ The degrees by which to rotate the image: positive values = clockwise rotation,
    #   negative values = counter-clockwise, 0 = force no rotation, +nil+ = rotate automatically when needed.
    #
    # Returns: +String+ A screenshot in the requested format.
    def screenshot_as(output_type, rotation = nil)
      screenshot = Applitools::Utils::ImageUtils.png_image_from_base64(driver.screenshot_as(:base64))
      Applitools::Selenium::Driver.normalize_rotation(self, screenshot, rotation)

      case output_type
      when :base64
        screenshot = Applitools::Utils::ImageUtils.base64_from_png_image(screenshot)
      when :png
        screenshot = Applitools::Utils::ImageUtils.bytes_from_png_image(screenshot)
      else
        raise Applitools::EyesError.new("Unsupported screenshot output type: #{output_type}")
      end

      screenshot.force_encoding('BINARY')
    end

    def mouse
      Applitools::Selenium::Mouse.new(self, driver.mouse)
    end

    def keyboard
      Applitools::Selenium::Keyboard.new(self, driver.keyboard)
    end

    def find_element(*args)
      how, what = extract_args(args)

      # Make sure that "how" is a valid locator.
      raise ArgumentError, "cannot find element by: #{how.inspect}" unless FINDERS[how.to_sym]

      Applitools::Selenium::Element.new(self, driver.find_element(how, what))
    end

    def find_elements(*args)
      how, what = extract_args(args)

      raise ArgumentError, "cannot find element by: #{how.inspect}" unless FINDERS[how.to_sym]

      driver.find_elements(how, what).map { |el| Applitools::Selenium::Element.new(self, el) }
    end

    def user_agent
      @user_agent ||= execute_script JS_GET_USER_AGENT
    rescue => e
      Applitools::EyesLogger.error "Failed to obtain user-agent string (#{e.message})"

      nil
    end

    private

    def driver
      @driver ||= __getobj__
    end

    def extract_args(args)
      case args.size
      when 2
        args
      when 1
        arg = args.first

        raise Argu mentError, "expected #{arg.inspect}:#{arg.class} to respond to #shift" unless arg.respond_to?(:shift)

        # This will be a single-entry hash, so use #shift over #first or #[].
        arg.dup.shift.tap do |arr|
          raise ArgumentError, "expected #{arr.inspect} to have 2 elements" unless arr.size == 2
        end
      else
        raise ArgumentError, "wrong number of arguments (#{args.size} for 2)"
      end
    end
  end
end