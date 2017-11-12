class SmartCampaign < ActiveRecord::Base

  has_many :smart_campaign_filters, dependent: :destroy
  has_many :smart_campaign_exclude_filters, dependent: :destroy

  has_one :smart_campaign_schedule, dependent: :destroy, class_name: "SmartCampaignSchedule"

  has_many :dependent_campaigns, class_name: 'SmartCampaign', foreign_key: :parent_id

  has_many :smart_campaign_histories, foreign_key: :campaign_id, dependent: :destroy
  has_many :smart_campaign_results, foreign_key: :campaign_id, dependent: :destroy

  has_many :smart_campaign_marketing_summaries, class: 'SmartCampaignMarketingSummary', foreign_key: :campaign_id

  belongs_to :sms_template
  belongs_to :smart_campaign_category
  belongs_to :email_template
  belongs_to :user
  belongs_to :salon
  belongs_to :parent_campaign, class_name: 'SmartCampaign', foreign_key: :parent_id

  accepts_nested_attributes_for :smart_campaign_schedule
  accepts_nested_attributes_for :smart_campaign_filters, reject_if: proc { |attributes| attributes['inputs'].blank? || attributes['data_filter_id'].blank? }, allow_destroy: true
  accepts_nested_attributes_for :smart_campaign_exclude_filters, reject_if: proc { |attributes| attributes['inputs'].blank? || attributes['data_filter_id'].blank? }, allow_destroy: true

  attr_accessor :sms_template_content, :email_template_subject, :email_template_token

  after_find{|sc| sc.sms_template_content = sc.sms_template.message if sc.sms_template }

  after_find{|sc| sc.email_template_subject = sc.email_template.subject if sc.email_template }

  after_update :update_sms_template, :update_email_subject, :check_campaign_category_id

  after_save :schedule_campaign

  before_destroy :delete_linked_sms_and_email_templates
  before_destroy :delete_linked_jobs

  scope :default, ->{ where(is_default: true) }
  scope :data_for_executed_between, ->(start_date, end_date) { includes(:smart_campaign_results).joins(:smart_campaign_histories).where("campaign_histories.executed_at BETWEEN ? AND ?", start_date.beginning_of_day, end_date.end_of_day)}
  scope :order_by_id, -> { order('id desc') }

  # Validations
  # validate :is_enabled_for_admin

  def delete_linked_jobs
    Delayed::Job.where(campaign_id: self.id, campaign_type: 'SmartCampaign').delete_all
  end

  def toggle_for(salon)
    if self.is_default?
      self.enable_for(salon)
    else
      self.is_enabled = !self.is_enabled
      self.save
    end
  end

  def toggle_is_enabled
    self.is_enabled = !self.is_enabled
    self.save
  end

  def enable_for(salon)
    ActiveRecord::Base.transaction do
      copy_campaign_for(salon)
    end
  end

  def is_enabled_for_admin
    if self.is_admin
      self.is_enabled = false;
      self.is_sms_enabled = false;
      self.is_email_enabled = false;
    end
  end


  def copy_campaign_for(salon)
    campaign = self.dup
    campaign.salon_id = salon.id
    campaign.parent_id = self.id
    campaign.is_default = false
    campaign.is_enabled = true
    if campaign.save
      copy_filters_for(campaign)
      self.sms_template ? copy_sms_template_for(campaign) : create_sms_template_for(campaign)
      self.email_template ? copy_email_template_for(campaign) : create_email_template_for(campaign)
      self.smart_campaign_schedule ? copy_schedule_for(campaign) : create_schedule_for(campaign)
    end
  end

  def check_campaign_category_id
    if self.smart_campaign_category_id.present?
      self.dependent_campaigns.each do |campaign|
        campaign.update_column(:smart_campaign_category_id, self.smart_campaign_category_id)
      end
    end
  end

  def copy_filters_for(campaign)
    self.smart_campaign_filters.each do |campaign_filter|
      new_filter = campaign_filter.dup
      new_filter.smart_campaign_id = campaign.id
      new_filter.save
    end
  end

  def copy_schedule_for(campaign)
    schedule = self.smart_campaign_schedule.dup
    schedule.smart_campaign_id = campaign.id
    schedule.save
  end

  def create_schedule_for(campaign)
    schedule = SmartCampaignSchedule.new
    schedule.smart_campaign_id = campaign.id
    schedule.save
  end

  def copy_sms_template_for(campaign)
    new_sms_template = self.sms_template.dup
    new_sms_template.is_default = false
    if new_sms_template.save
      campaign.update_column(:sms_template_id, new_sms_template.id)
    end
  end

  def create_sms_template_for(campaign)
    new_sms_template = SmsTemplate.new
    new_sms_template.is_default = false
    if new_sms_template.save
      campaign.update_column(:sms_template_id, new_sms_template.id)
    end
  end

  def copy_email_template_for(campaign)
    new_email_template = self.email_template.dup
    new_email_template.is_default = false
    new_email_template.template_token = SecureRandom.hex(4)
    if new_email_template.save
      campaign.update_column(:email_template_id, new_email_template.id)
    end
  end

  def create_email_template_for(campaign)
    new_email_template = EmailTemplate.new
    new_email_template.is_default = false
    new_email_template.template_token = SecureRandom.hex(4)
    if new_email_template.save
      campaign.update_column(:email_template_id, new_email_template.id)
    end
  end

  def update_sms_template
    unless self.sms_template_content.blank?
      sms_template = self.sms_template || SmsTemplate.new
      sms_template.message = self.sms_template_content
      if sms_template.save
        self.update_column(:sms_template_id, sms_template.id)
      end
    end
  end

  def update_email_subject
    unless self.email_template_subject.blank?
      email_template = EmailTemplate.find_or_initialize_by(template_token: self.email_template_token)
      email_template.template_token = self.email_template_token
      email_template.subject = self.email_template_subject
      if email_template.save
        self.update_column(:email_template_id, email_template.id)
      end
    end
  end

  def delete_linked_sms_and_email_templates
    unless is_default?
      self.sms_template.destroy if self.sms_template
      self.email_template.destroy if self.email_template
    end
  end

  def self.find_for_user(user, salon_id = nil)
    user_salons = user.salons.map(&:id)
    salon_id = user_salons.first if salon_id.blank?
    salon_campaigns = SmartCampaign.where(salon_id: salon_id)
    if salon_campaigns.any?
      SmartCampaign.where("(salon_id in (?)) OR (is_default = ? and id  not in (?))", salon_id, true, salon_campaigns.map(&:parent_id)).order('updated_at DESC')
    else
      default
    end
  end

  def execute
    SalonLogger.current_salon_log = SalonLogger.create(log_class:self.class,log_id:self.id,log_type:"SMART_CAMPAING",executed_at:DateTime.now,content:{"message": "Started execution of #{self.name}", "client_ids": [],"error_trace":'',"sms_log": {},"email_log": {},"schedule_log": ''})
    begin
      clients = filter_clients
      SalonLogger.current_salon_log.content["client_ids"]=clients.pluck(:id)
      SalonLogger.current_salon_log.save
      execute_campaigns_for(clients)
      schedule_next_campaign
    rescue => e
      SalonLogger.current_salon_log.content["error_trace"]=e.message+'\n'+e.backtrace.join(' ')
      SalonLogger.current_salon_log.save
    end
  end

  def schedule_next_campaign
    self.smart_campaign_schedule.schedule_smart_campaign
  end

  def filter_clients
    sent_clients = executed_clients
    mkt_filter = MarketingFilter.new({salon_ids: [self.salon_id], search: generate_filter_params(:smart_campaign_filters)}, self.user)
    sent_clients.blank? ? mkt_filter.search : mkt_filter.search.where("clients.ext_id not in (?)", sent_clients)
  end

  def executed_clients
    self.notification_frequency ||= 0
    excluded_client_ids = SmartCampaignHistory.where("campaign_id = ? AND salon_id = ? AND DATE(executed_at) BETWEEN (?) AND (?)", self.id, self.salon_id, (Date.today - notification_frequency.day), Date.today).map(&:client_id)
    if self.smart_campaign_exclude_filters.any?
      mkt_filter = MarketingFilter.new({salon_ids: [self.salon_id], search: generate_filter_params(:smart_campaign_exclude_filters)}, self.user)
      excluded_client_ids = mkt_filter.search.map('ext_id')
    end
    excluded_client_ids
  end

  def generate_filter_params(filter_type)
    filter_hash = {:filter => {}}
    self.send(filter_type).each do |campaign_filter|
      filter_hash[:filter]["#{campaign_filter.data_filter_id}"] = {'input' => campaign_filter.inputs}
    end
    filter_hash
  end

  def execute_campaigns_for(clients)
    clients.each do |client|
      execute_sms_campaign_for(client) if sms_preference_set?(client)
      execute_email_campaign_for(client) if email_preference_set?(client)
    end
  end

  def execute_sms_campaign_for(client)
    content = sms_template.interpolate_template_for(client)
    unless content.blank?
      sms_resp = send_sms_to(client, content)
      create_log(client, content, 'sms', sms_resp)
      SalonLogger.current_salon_log.content["sms_log"][client.id.to_s] = sms_resp.to_s
      SalonLogger.current_salon_log.save
    end
    sms_template.reload
  end

  def execute_email_campaign_for(client)
    content = email_template.interpolate_template_for(client)
    subject = email_template.interpolate_subject_for(client)
    marketing_user_email = self.salon.marketing_from_email
    unless content.blank?
      send_mail_to(client, subject, content, marketing_user_email)
      create_log(client, content, 'email')
      SalonLogger.current_salon_log.content["email_log"][client.id.to_s] = "Send mail to #{client.email}"
      SalonLogger.current_salon_log.save
    end
    email_template.reload
  end

  def send_sms_to(client, content)
    s = SmsApiWrapper.new
    s.send_sms(client.salon_id, "44#{client.mobile_no}", client.salon.name, content)
  end

  def send_mail_to(client, subject, content, marketing_from_email)
    send_to = client.email
    marketing_user_email = self.salon.marketing_from_email
    CampaignMailer.send_email(send_to, subject, content, marketing_user_email, {}).deliver_now if send_to.present?
  end

  def create_log(client, content, type, response = {})
    self.smart_campaign_histories.create(client_id: client.ext_id, salon_id: client.salon_id, segment_type: type, executed_at: Time.now, content: content, track_upto: ( (Date.today + self.tracking_period.days) rescue nil), response: response.as_json)
  end

  def self.fetch_smart_campaign(start_date, end_date)
    data_for_executed_between(start_date, end_date).order_by_id
  end

  def sms_preference_set?(client)
    return false if client.mobile_no.blank?
    pref = false
    if sms_template.present? && sms_template.content.present?
      if ['text_only', 'both', 'texts_then_emails'].include?(exec_pref)
        pref = true
      elsif (exec_pref == 'emails_then_texts' && client.email.blank?)
        pref = true
      end
    end
    pref
  end

  def email_preference_set?(client)
    return false if client.email.blank?
    pref = false
    if email_template.present? && email_template.content.present?
      if ['email_only', 'both', 'emails_then_texts'].include?(exec_pref)
        pref = true
      elsif (exec_pref == 'texts_then_emails' && client.mobile_no.blank?)
        pref = true
      end
    end
    pref
  end

  def schedule_campaign
    self.smart_campaign_schedule.try(:schedule_smart_campaign)
  end

  def revert!
    @parent_campaign = self.parent_campaign
    revert_campaign_settings
    revert_sms_template
    revert_email_template
    revert_schedule_settings
    revert_campaign_filters
  end

  def revert_campaign_settings
    if @parent_campaign
      parent_attributes = @parent_campaign.attributes
      ['is_default', 'user_id', 'parent_id', 'created_at', 'updated_at', 'sms_template_id', 'email_template_id', 'id'].each{|attri| parent_attributes.delete(attri)}
      self.update_attributes(parent_attributes)
    end
  end

  def revert_sms_template
    if @parent_campaign
      parent_sms_template = @parent_campaign.sms_template
      if parent_sms_template
        template_attributes = parent_sms_template.attributes
        ['id', 'is_default', 'user_id', 'created_at', 'updated_at'].each{|attri| template_attributes.delete(attri)}
        self.sms_template.update_attributes(template_attributes)
      else
        attribs = { from_name: nil, message: nil, name: nil }
        self.sms_template.update_attributes(attribs)
      end
    end
  end

  def revert_email_template
    if @parent_campaign
      parent_email_template = @parent_campaign.email_template
      if parent_email_template
        template_attributes = parent_email_template.attributes
        ['id', 'is_default', 'user_id', 'created_at', 'updated_at', 'template_token'].each{|attri| template_attributes.delete(attri)}
        self.email_template.update_attributes(template_attributes)
      else
        attribs = { template_name: nil, from_name: nil, subject: nil, from_address: nil, content: nil }
        self.email_template.update_attributes(attribs)
      end
    end
  end

  def revert_schedule_settings
    if @parent_campaign
      parent_campaign_schedule = @parent_campaign.smart_campaign_schedule
      if parent_campaign_schedule
        schedule_attributes = parent_campaign_schedule.attributes
        ['id', 'created_at', 'updated_at', 'smart_campaign_id', 'segment_id'].each{|attri| schedule_attributes.delete(attri)}
        self.smart_campaign_schedule.update_attributes(schedule_attributes)
      else
        attribs = { cron_expression: nil, run_at_time: nil, start_date: nil, end_date: nil, frequency:nil, run_at_day: nil, week_day: nil }
        self.smart_campaign_schedule.update_attributes(attribs)
      end
    end
  end

  def revert_campaign_filters
    if @parent_campaign
      @parent_campaign.smart_campaign_filters.each do |filter|
        current_filter_obj = self.smart_campaign_filters.find_by(data_filter_id: filter.data_filter_id)
        current_filter_obj.inputs = filter.inputs
        current_filter_obj.save
      end
    end
  end

  def status_for(salon)
    active_for?(salon) ? 'Active' : 'Inactive'
  end

  def active_for?(salon)
    status = false
    dependent_campaigns.each{|c| status = true if c.salon_id == salon.id && c.is_enabled }
    status
  end


end
