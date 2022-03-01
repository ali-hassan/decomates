class HomepageController < ApplicationController

  before_action :save_current_path, :except => :sign_in

  APP_DEFAULT_VIEW_TYPE = "grid".freeze
  VIEW_TYPES_NO_LOCATION = ["grid".freeze, "list".freeze].freeze
  VIEW_TYPES = (VIEW_TYPES_NO_LOCATION + ["map".freeze]).freeze

  # rubocop:disable AbcSize
  # rubocop:disable MethodLength
  def index
    params = unsafe_params_hash.select{|k, v| v.present? }
    if params["q"].present?
      unless check_zipcode?
        flash["error"] = "unfortunately we are currently not delivering to your area"
      else
        flash["notice"] = "Great, We are delivering to your area."
      end
    end

    redirect_to landing_page_path and return if no_current_user_in_private_clp_enabled_marketplace?

    all_shapes = @current_community.shapes
    shape_name_map = all_shapes.map { |s| [s[:id], s[:name]]}.to_h

    filter_params = {}

    m_selected_category = Maybe(@current_community.categories.find_by_url_or_id(params[:category]))
    filter_params[:categories] = m_selected_category.own_and_subcategory_ids.or_nil
    selected_category = m_selected_category.or_nil
    relevant_filters = select_relevant_filters(m_selected_category.own_and_subcategory_ids.or_nil)
    @seo_service.category = selected_category

    if FeatureFlagHelper.feature_enabled?(:searchpage_v1)
      @view_type = "grid"
    else
      @view_type = SearchPageHelper.selected_view_type(params[:view], @current_community.default_browse_view, APP_DEFAULT_VIEW_TYPE, allowed_view_types)
      @big_cover_photo = !(@current_user || CustomLandingPage::LandingPageStore.enabled?(@current_community.id)) || params[:big_cover_photo]

      @categories = @current_community.categories.includes(:children)
      @main_categories = @categories.select { |c| c.parent_id == nil }

      # This assumes that we don't never ever have communities with only 1 main share type and
      # only 1 sub share type, as that would make the listing type menu visible and it would look bit silly
      listing_shape_menu_enabled = all_shapes.size > 1
      @show_categories = @categories.size > 1
      show_price_filter = @current_community.show_price_filter && all_shapes.any? { |s| s[:price_enabled] }

      @show_custom_fields = relevant_filters.present? || show_price_filter
      @category_menu_enabled = @show_categories || @show_custom_fields

      if @show_categories
        @category_display_names = category_display_names(@current_community, @categories)
      end
    end

    listing_shape_param = params[:transaction_type]

    selected_shape = all_shapes.find { |s| s[:name] == listing_shape_param }

    filter_params[:listing_shape] = Maybe(selected_shape)[:id].or_else(nil)

    compact_filter_params = HashUtils.compact(filter_params)

    per_page = @view_type == "map" ? APP_CONFIG.map_listings_limit : APP_CONFIG.grid_listings_limit

    includes =
      case @view_type
      when "grid"
        [:author, :listing_images]
      when "list"
        [:author, :listing_images, :num_of_reviews]
      when "map"
        [:location]
      else
        raise ArgumentError.new("Unknown view_type #{@view_type}")
      end

    main_search = search_mode
    enabled_search_modes = search_modes_in_use(params[:q], params[:lc], main_search)
    keyword_in_use = enabled_search_modes[:keyword]
    location_in_use = enabled_search_modes[:location]

    current_page = Maybe(params)[:page].to_i.map { |n| n > 0 ? n : 1 }.or_else(1)
    relevant_search_fields = parse_relevant_search_fields(params, relevant_filters)

    search_result = find_listings(params: params,
                                  current_page: current_page,
                                  listings_per_page: per_page,
                                  filter_params: compact_filter_params,
                                  includes: includes.to_set,
                                  location_search_in_use: location_in_use,
                                  keyword_search_in_use: keyword_in_use,
                                  relevant_search_fields: relevant_search_fields)

    if @view_type == 'map'
      viewport = viewport_geometry(params[:boundingbox], params[:lc], @current_community.location)
    end

    if FeatureFlagHelper.feature_enabled?(:searchpage_v1)
      search_result.on_success { |listings|
        render layout: "layouts/react_page.haml", template: "search_page/search_page", locals: { props: searchpage_props(listings, current_page, per_page) }
      }.on_error {
        flash[:error] = t("homepage.errors.search_engine_not_responding")
        render layout: "layouts/react_page.haml", template: "search_page/search_page", locals: { props: searchpage_props(nil, current_page, per_page) }
      }
    elsif request.xhr? # checks if AJAX request
      search_result.on_success { |listings|
        @listings = listings # TODO Remove

        if @view_type == "grid" then
          render partial: "grid_item", collection: @listings, as: :listing, locals: { show_distance: location_in_use }
        elsif location_in_use
          render partial: "list_item_with_distance", collection: @listings, as: :listing, locals: { shape_name_map: shape_name_map, show_distance: location_in_use }
        else
          render partial: "list_item", collection: @listings, as: :listing, locals: { shape_name_map: shape_name_map }
        end
      }.on_error {
        render body: nil, status: :internal_server_error
      }
    else
      locals = {
        shapes: all_shapes,
        filters: relevant_filters,
        show_price_filter: show_price_filter,
        selected_category: selected_category,
        selected_shape: selected_shape,
        shape_name_map: shape_name_map,
        listing_shape_menu_enabled: listing_shape_menu_enabled,
        main_search: main_search,
        location_search_in_use: location_in_use,
        current_page: current_page,
        current_search_path_without_page: search_path(params.except(:page)),
        viewport: viewport,
        search_params: CustomFieldSearchParams.remove_irrelevant_search_params(params, relevant_search_fields)
      }

      search_result.on_success { |listings|
        @listings = listings
        render locals: locals.merge(
                 seo_pagination_links: seo_pagination_links(params, @listings.current_page, @listings.total_pages))
      }.on_error { |e|
        flash[:error] = t("homepage.errors.search_engine_not_responding")
        @listings = Listing.none.paginate(:per_page => 1, :page => 1)
        render status: :internal_server_error,
               locals: locals.merge(
                 seo_pagination_links: seo_pagination_links(params, @listings.current_page, @listings.total_pages))
      }
    end
  end
  # rubocop:enable AbcSize
  # rubocop:enable MethodLength

  helper_method :allowed_view_types

  def allowed_view_types
    show_location? ? VIEW_TYPES : VIEW_TYPES_NO_LOCATION
  end

  private

  def parse_relevant_search_fields(params, relevant_filters)
    search_filters = SearchPageHelper.parse_filters_from_params(params)
    checkboxes = search_filters[:checkboxes]
    dropdowns = search_filters[:dropdowns]
    numbers = filter_unnecessary(search_filters[:numeric], @current_community.custom_numeric_fields)
    search_fields = checkboxes.concat(dropdowns).concat(numbers)

    SearchPageHelper.remove_irrelevant_search_fields(search_fields, relevant_filters)
  end

  def find_listings(params:, current_page:, listings_per_page:, filter_params:, includes:, location_search_in_use:, keyword_search_in_use:, relevant_search_fields:)

    search = {
      # Add listing_id
      categories: filter_params[:categories],
      listing_shape_ids: Array(filter_params[:listing_shape]),
      price_cents: filter_range(params[:price_min], params[:price_max]),
      keywords: keyword_search_in_use ? params[:q] : nil,
      fields: relevant_search_fields,
      per_page: listings_per_page,
      page: current_page,
      price_min: params[:price_min],
      price_max: params[:price_max],
      locale: I18n.locale,
      include_closed: false,
      sort: nil
    }

    if @view_type != 'map' && location_search_in_use
      search.merge!(location_search_params(params, keyword_search_in_use))
    end

    raise_errors = Rails.env.development?

    if FeatureFlagHelper.feature_enabled?(:searchpage_v1)
      DiscoveryClient.get(:query_listings,
                          params: DiscoveryUtils.listing_query_params(search.merge(marketplace_id: @current_community.id)))
      .rescue {
        Result::Error.new(nil, code: :discovery_api_error)
      }
        .and_then{ |res|
        Result::Success.new(res[:body])
      }
    else
      ListingIndexService::API::Api.listings.search(
        community_id: @current_community.id,
        search: search,
        includes: includes,
        engine: FeatureFlagHelper.search_engine,
        raise_errors: raise_errors
        ).and_then { |res|
        Result::Success.new(
          ListingIndexViewUtils.to_struct(
            result: res,
            includes: includes,
            page: search[:page],
            per_page: search[:per_page]
          )
        )
      }
    end
  end

  # Time to cache category translations per locale
  CATEGORY_DISPLAY_NAME_CACHE_EXPIRE_TIME = 24.hours

  def category_display_names(community, categories)
    Rails.cache.fetch(["catnames",
                       community,
                       I18n.locale,
                       categories],
                      expires_in: CATEGORY_DISPLAY_NAME_CACHE_EXPIRE_TIME) do
      cat_names = {}
      categories.each do |cat|
        cat_names[cat.id] = cat.display_name(I18n.locale)
      end
      cat_names
    end
  end

  def location_search_params(params, keyword_search_in_use)
    marketplace_configuration = @current_community.configuration

    distance = params[:distance_max].to_f
    distance_system = marketplace_configuration ? marketplace_configuration[:distance_unit].to_sym : nil
    distance_unit = distance_system == :metric ? :km : :miles
    limit_search_distance = marketplace_configuration ? marketplace_configuration[:limit_search_distance] : true
    distance_limit = [distance, APP_CONFIG[:external_search_distance_limit_min].to_f].max if limit_search_distance

    corners = params[:boundingbox].split(',') if params[:boundingbox].present?
    center_point = if limit_search_distance && corners&.length == 4
      LocationUtils.center(*corners.map { |n| LocationUtils.to_radians(n) })
    else
      search_coordinates(params[:lc])
    end

    scale_multiplier = APP_CONFIG[:external_search_scale_multiplier].to_f
    offset_multiplier = APP_CONFIG[:external_search_offset_multiplier].to_f
    combined_search_in_use = keyword_search_in_use && scale_multiplier && offset_multiplier
    combined_search_params = if combined_search_in_use
      {
        scale: [distance * scale_multiplier, APP_CONFIG[:external_search_scale_min].to_f].max,
        offset: [distance * offset_multiplier, APP_CONFIG[:external_search_offset_min].to_f].max
      }
    else
      {}
    end

    sort = :distance unless combined_search_in_use

    {
      distance_unit: distance_unit,
      distance_max: distance_limit,
      sort: sort
    }
    .merge(center_point)
    .merge(combined_search_params)
    .compact
  end

  # Filter search params if their values equal min/max
  def filter_unnecessary(search_params, numeric_fields)
    search_params.reject do |search_param|
      numeric_field = numeric_fields.find(search_param[:id])
      search_param.slice(:id, :value) == { id: numeric_field.id, value: (numeric_field.min..numeric_field.max) }
    end
  end

  def filter_range(price_min, price_max)
    if (price_min && price_max)
      min = MoneyUtil.parse_str_to_money(price_min, @current_community.currency).cents
      max = MoneyUtil.parse_str_to_money(price_max, @current_community.currency).cents

      if ((@current_community.price_filter_min..@current_community.price_filter_max) != (min..max))
        (min..max)
      else
        nil
      end
    end
  end

  def search_coordinates(latlng)
    lat, lng = latlng.split(',')
    if(lat.present? && lng.present?)
      return { latitude: lat, longitude: lng }
    else
      ArgumentError.new("Format of latlng coordinate pair \"#{latlng}\" wasn't \"lat,lng\" ")
    end
  end

  def no_current_user_in_private_clp_enabled_marketplace?
    CustomLandingPage::LandingPageStore.enabled?(@current_community.id) &&
      @current_community.private &&
      !@current_user
  end

  def search_modes_in_use(q, lc, main_search)
    # lc should be two decimal coordinates separated with a comma
    # e.g. 65.123,-10
    coords_valid = /^-?\d+(?:\.\d+)?,-?\d+(?:\.\d+)?$/.match(lc)
    {
      keyword: q && [:keyword, :keyword_and_location].include?(main_search),
      location: coords_valid && [:location, :keyword_and_location].include?(main_search)
    }
  end

  def viewport_geometry(boundingbox, lc, community_location)
    coords = Maybe(boundingbox).split(',').or_else(nil)
    if coords
      sw_lat, sw_lng, ne_lat, ne_lng = coords
      { boundingbox: { sw: [sw_lat, sw_lng], ne: [ne_lat, ne_lng] } }
    elsif lc.present?
      { center: lc.split(',') }
    else
      Maybe(community_location)
        .map { |l| { center: [l.latitude, l.longitude] }}
        .or_else(nil)
    end
  end

  def seo_pagination_links(params, current_page, total_pages)
    prev_page =
      if current_page > 1
        search_path(params.merge(page: current_page - 1))
      end

    next_page =
      if current_page < total_pages
        search_path(params.merge(page: current_page + 1))
      end

    {
      prev: prev_page,
      next: next_page
    }
  end

  def searchpage_props(bootstrapped_data, page, per_page)
    SearchPageHelper.searchpage_props(
      page: page,
      per_page: per_page,
      bootstrapped_data: bootstrapped_data,
      notifications_to_react: notifications_to_react,
      display_branding_info: display_branding_info?,
      community: @current_community,
      path_after_locale_change: @return_to,
      user: @current_user,
      search_placeholder: @community_customization&.search_placeholder,
      current_path: request.fullpath,
      locale_param: params[:locale],
      host_with_port: request.host_with_port)
  end

  # Database select for "relevant" filters based on the `category_ids`
  #
  # If `category_ids` is present, returns only filter that belong to
  # one of the given categories. Otherwise returns all filters.
  #
  def select_relevant_filters(category_ids)
    relevant_filters =
      if category_ids.present?
        @current_community
          .custom_fields
          .joins(:category_custom_fields)
          .where("category_custom_fields.category_id": category_ids, search_filter: true)
          .distinct
      else
        @current_community
          .custom_fields.where(search_filter: true)
      end

    relevant_filters.sort
  end

  def unsafe_params_hash
    params.to_unsafe_hash
  end

  def all_zipcodes
    [2000, 2006, 2007, 2008, 2009, 2010, 2011, 2015, 2016, 2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024, 2025, 2026, 2027, 2028, 2029, 2030, 2031, 2032, 2033, 2034, 2035, 2036, 2037, 2038, 2039, 2040, 2041, 2042, 2043, 2044, 2045, 2046, 2047, 2048, 2049, 2050, 2060, 2061, 2062, 2063, 2064, 2065, 2066, 2067, 2068, 2069, 2070, 2071, 2072, 2073, 2074, 2075, 2076, 2077, 2085, 2086, 2087, 2088, 2089, 2090, 2092, 2093, 2094, 2096, 2099, 2100, 2109, 2110, 2111, 2112, 2113, 2114, 2115, 2116, 2117, 2118, 2119, 2120, 2121, 2122, 2125, 2126, 2127, 2128, 2130, 2131, 2132, 2133, 2134, 2135, 2136, 2137, 2138, 2140, 2141, 2142, 2143, 2144, 2145, 2146, 2147, 2148, 2150, 2151, 2152, 2153, 2154, 2155, 2156, 2160, 2161, 2162, 2163, 2164, 2165, 2166, 2167, 2168, 2170, 2171, 2172, 2173, 2174, 2175, 2176, 2177, 2178, 2179, 2190, 2191, 2192, 2193, 2194, 2195, 2196, 2197, 2198, 2199, 2200, 2203, 2204, 2205, 2206, 2207, 2208, 2209, 2210, 2211, 2212, 2213, 2214, 2216, 2217, 2218, 2219, 2220, 2221, 2222, 2223, 2224, 2225, 2226, 2227, 2228, 2229, 2230, 2232, 2233, 2234, 2557, 2558, 2559, 2560, 2564, 2565, 2566, 2567, 2570, 2745, 2747, 2749, 2750, 2759, 2760, 2761, 2762, 2763, 2765, 2766, 2767, 2768, 2769, 2770, 2001, 2002, 2003, 2004, 2005, 2013, 2014, 2051, 2053, 2054, 2055, 2056, 2057, 2058, 2059, 2078, 2098, 2123, 2124, 2129, 2149, 2169, 2180, 2181, 2182, 2183, 2184, 2185, 2186, 2187, 2188, 2189, 2201, 2202, 2215, 2235, 2236, 2237, 2238, 2239, 2240, 2241, 2242, 2243, 2244, 2245, 2246, 2247, 2248, 2249, 2740, 2741, 2742, 2743, 2744, 2751, 2764, 2771, 2772, 2891, 2892, 2893, 2894, 2895, 2896, 2897,
      2012, 2091, 2754, 2755, 2773, 2774, 2776, 2778, 2779, 2780, 2782, 2783, 2784, 2785, 2052, 2079, 2080, 2081, 2082, 2084, 2095, 2097, 2101, 2102, 2103, 2104, 2105, 2106, 2107, 2108, 2139, 2157, 2158, 2159, 2231, 2555, 2556, 2748, 2753, 2756, 2083, 2563, 2890, 2509, 2510, 2511, 2512, 2513, 2514, 2561, 2562, 2746, 2781]
  end
  def check_zipcode?
    all_zipcodes.include?(get_zipcode.try(:to_i))
  end
  def get_zipcode
    results = Geocoder.search(params["q"])
    results.last.data["address"]["postcode"]
  end
end
