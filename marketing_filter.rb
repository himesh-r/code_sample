class MarketingFilter

  attr_accessor :params, :data_filters, :filter_conditions, :salon_ids, :user

  def initialize(params = {}, current_user)
    @params = params
    @user = current_user
    @salon_ids = salon_ids
    @data_filters = fetch_filters
    @filter_categories = fetch_filter_categories
    @filter_conditions = []
    @join_conditions = []
    @join_tables = []
  end

  def salon_ids
    @params[:salon_ids].split(',').select{|s| !s.blank? }
  end

  def fetch_filters
    filters = {}
    DataFilter.all.collect{|df| filters[df.id.to_s] = df.attributes.except('created_at', 'updated_at', 'id')}
    filters
  end

  def fetch_filter_categories
    filters = {}
    DataFilterCategory.all.collect{|df| filters[df.id.to_s] = df.attributes.except('created_at', 'updated_at')}
    filters
  end

  def search
    apply_salons_filter
    generate_conditions
    execute_search
  end

  def execute_search
    applicable_clients.joins(join_criteria).where(filter_criteria).order(sort_condition)
  end

  def applicable_clients
    salons = !@salon_ids.blank? ? @salon_ids : user_salon_ids
    Client.where(salon_id: salons)
  end

  def user_salon_ids
    @user.present? ? @user.salons.map(&:id) : Salon.all.map(&:id)
  end

  def filter_criteria
    @filter_conditions.join(' AND ')
  end

  def join_criteria
    @join_conditions.reject!{|i| i.blank?}
    if !@join_conditions.compact.blank?
      @join_conditions.flatten.map(&:strip).uniq.join(' ')
      @join_tables = @join_tables.compact.flatten.uniq
      @join_tables.each do |table_name|
        delete_dependencies_for(table_name)
      end
      join_queries = []
      @join_tables.each do |table_name|
        join_queries << eval("join_for_#{table_name}")
      end
      join_queries.flatten.uniq.join(' ')
    else
      ''
    end
  end

  def apply_salons_filter
    @salon_ids.any? ? "clients.salon_id in #{@salon_ids}" : nil
  end

  def sort_condition
    column, order = @params['sort'].split('-') rescue ['first_name', 'asc']
    "#{column} #{order}"
  end

  # params structure passed from view - search[filter][1][input][0]
  def generate_conditions
    if @params[:search]
      @params[:search][:filter].each do |key, val|
        filter = @data_filters[key]
        if filter['id_filter']
          client_ids = send(filter['id_query_method'], val['input'])
          condition = client_ids.any? ? "clients.id in ( #{client_ids.join(',')} )" : ""
        else
          condition = filter['query_string']
          next if val['input'].values.include?("")
          val['input'].each do |index, val|
            parsed_val = parse_input_val(filter['input_type'], filter['query_input_type'], val, condition)
            condition.gsub!("{{input_#{(index.to_i)}}}", parsed_val.to_s)
          end
        end
        @filter_conditions << condition unless condition.blank?
        @join_conditions << filter['join_condition']
        @join_tables << filter['join_tables']
      end
    end
  end

  def parse_input_val(input_type, query_input_type, input_value, condition)
    if input_type == 'select' && input_value.is_a?(Array)
      input_value.compact.join(', ')
    elsif condition.match(/how_heard_id/)
      convert_id_to_how_heard_id(input_value)
    elsif condition.match(/last_team_member/)
      convert_id_to_team_member_id(input_value)
    else
      send("to_#{query_input_type}", input_value)
    end
  end

  # This method returns postgres specific boolean value. Must not be changed
  def to_boolean(input_value)
    input_value == 'true' ? 't' : 'f'
  end

  def to_date(input_value)
    (Date.today - input_value.to_i.day)
  end

  def to_integer(input_value)
    input_value.to_i
  end

  def to_float(input_value)
    input_value.to_f
  end

  def to_string(input_value)
    input_value.to_s
  end

  def convert_id_to_how_heard_id(id)
    HowHeard.find(id).ext_id
  end

  def convert_id_to_team_member_id(id)
    TeamMember.find(id).ext_id
  end

  def delete_dependencies_for(table_name)
    @join_tables = (@join_tables - eval("#{table_name}_dependencies"))
  end

  def payments_dependencies
    []
  end

  def payment_details_dependencies
    ['payments']
  end

  def products_dependencies
    ['payments', 'payment_details']
  end

  def product_categories_dependencies
    ['payments', 'payment_details', 'products']
  end

  def services_dependencies
    ['payments', 'payment_details']
  end

  def service_categories_dependencies
    ['payments', 'payment_details', 'services']
  end

  def bookings_dependencies
    []
  end

  def booking_details_dependencies
    ['bookings']
  end

  def join_for_payments
    [join_payments]
  end

  def join_for_payment_details
    [join_payments, join_payment_details]
  end

  def join_for_bookings
    [join_bookings]
  end

  def join_for_booking_details
    [join_bookings, join_booking_details]
  end

  def join_for_products
    [join_payments, join_payment_details, join_products]
  end

  def join_for_product_categories
    [join_payments, join_payment_details, join_products, join_product_categories]
  end

  def join_for_services
    [join_payments, join_payment_details, join_services]
  end

  def join_for_service_categories
    [join_payments, join_payment_details, join_services, join_service_categories]
  end

  def join_salons
    'inner join salons on (clients.salon_id = salons.id)'
  end

  def join_bookings
    'inner join bookings on (bookings.client_id = clients.ext_id and bookings.salon_id = clients.salon_id)'
  end

  def join_booking_details
    'inner join booking_details on (bookings.ext_id = booking_details.booking_id and bookings.salon_id = booking_details.salon_id)'
  end

  def join_payments
    'inner join payments on (payments.client_id = clients.ext_id and payments.salon_id = clients.salon_id)'
  end

  def join_payment_details
    'inner join payment_details on (payment_details.payment_id = payments.ext_id and payments.salon_id = payment_details.salon_id)'
  end

  def join_products
    'inner join products on (payment_details.product_id = products.ext_id and payment_details.salon_id = products.salon_id)'
  end

  def join_product_categories
    'inner join product_categories on (products.product_category_id = product_categories.ext_id and products.salon_id = product_categories.salon_id)'
  end

  def join_services
    'inner join services on (payment_details.service_id = services.ext_id and payment_details.salon_id = services.salon_id)'
  end

  def join_service_categories
    'inner join service_categories on (services.service_category_id = service_categories.ext_id and services.salon_id = service_categories.salon_id)'
  end

  def service_spend_between(query_params)
    salon_ids = self.salon_ids.flatten.compact
    s_ids = salon_ids.any? ? "'#{salon_ids.join('\',\'')}'" : 'NULL'
    date_1 = Date.today - (query_params['date_val_2'].to_i).send(query_params['date_unit'])
    date_2 = Date.today - (query_params['date_val_1'].to_i).send(query_params['date_unit'])
    sql = "select clients.id, sum(payments.service_amount) as service_amount
      from clients
      inner join payments
      on (payments.client_id = clients.ext_id and payments.salon_id = clients.salon_id)
      where DATE(payment_date) between DATE('#{date_1}') and DATE('#{date_2}')
      AND service_amount #{query_params['equality_condition']} #{query_params['equality_value']}
      AND clients.salon_id in (#{s_ids})
      group by clients.id"
    Client.find_by_sql(sql).map(&:id)
  end

end

