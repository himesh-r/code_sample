class FullyBookdFbCampaign

  include TemplateInterpolator

  attr_accessor :salon, :facebook_setting, :appointments, :message, :postings

  def initialize(salon_id, user_id)
    @salon = Salon.find(salon_id)
    @facebook_setting = FacebookSetting.find_by(salon_id: salon_id, user_id: user_id)
    @postings = []
    @appointments = []
    @message = ''
    @user = User.find(user_id)
  end

  def execute
    generate_appointments
    generate_fully_bookd_postings
    generate_message
    post_message_to_facebook unless @postings.blank?
    @facebook_setting.update_scheduler
  end

  def generate_appointments
    @appointments = @facebook_setting.social_media_appointmemts
  end

  def generate_fully_bookd_postings
    @appointments.each do |day_data|
      day_data.each do |date, bookings|
        bookings.each do |booking|
          team_member, service_details = booking['team_member'], booking['random_service']
          zoned_time = service_details[:booking_date]
          fbp = FullyBookdPosting.new(salon_id: @salon.id, team_member_id: team_member.ext_id, service_id: service_details[:service_id], linked_service_id: service_details[:linked_service_id])
          @postings << fbp if fbp.save
        end
      end
    end
  end

  def generate_message
    @message = [interpolate_header, interpolate_body, interpolate_footer].join("%0D%0A%0D%0A")
  end

  def interpolate_header
    interpolate_fb_header_footer_content(@facebook_setting.post_header, self)
  end

  def interpolate_body
    content = ''
    @postings.each do |posting|
      content += (interpolate_fb_campaign_content(@facebook_setting.post_template, posting) + "%0D%0A%0D%0A")
      @facebook_setting.reload
    end
    content
  end

  def interpolate_footer
    interpolate_fb_header_footer_content(@facebook_setting.post_footer, self)
  end

  def post_message_to_facebook
    resp = @user.post_to_fb_page(nil, @message)
    @postings.each{|p| p.update_attribute(:facebook_post_id, resp['id'])} if resp['id']
  end

  def salon_name
    @salon.name
  end

  def salon_tel_no
    @salon.salon_setting.try(:phone_number)
  end

  def online_booking_url
    url = ENV['OLB_URL']
  end

end
