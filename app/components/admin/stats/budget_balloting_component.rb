class Admin::Stats::BudgetBallotingComponent < ApplicationComponent
  attr_reader :budget, :precision, :type
  use_helpers :include_stat_graphs_javascript, :render_map

  def initialize(budget, precision: 2, type: "vote")
    @budget = budget
    @precision = (precision.presence || 2).to_i
    @type = type
  end

  def vote_count
    stats.total_votes
  end

  def user_count
    stats.total_participants_vote_phase
  end

  def vote_count_by_heading
    # Optimization: Joins translations to get names without N+1 queries
    budget.lines.joins(heading: :translations)
          .where(budget_heading_translations: { locale: I18n.locale })
          .group("budget_heading_translations.name")
          .count.sort
  end

  def user_count_by_heading
    budget.headings.map do |heading|
      [heading.name, headings_stats[heading.id][:total_participants_vote_phase]]
    end.select { |_, count| count > 0 }.sort
  end

  def cluster_summary
    @cluster_summary ||= ConnectionAudit.where(auditable: budget.ballots)
                                        .combined_participation_stats(precision)
  end

  def voter_coordinates
    cluster_summary.map do |cluster|
      {
        lat: cluster.lat_cluster,
        long: cluster.lng_cluster,
        title: "#{cluster.voter_count} Voters",
        link: helpers.login_audit_details_admin_stats_path(
          lat: cluster.lat_cluster,
          lng: cluster.lng_cluster,
          precision: precision,
          type: type
        )
      }
    end
  end

  def geozones_data
    @geozones_data ||= active_geozones.map do |zone|
      {
        outline_points: zone.geojson,
        color: zone.color,
        name: zone.name,
        headings: [zone.name]
      }
    end
  end

  def precision_label
    case precision
    when 1 then t("admin.stats.budgets.precisions.district")
    when 2 then t("admin.stats.budgets.precisions.neighborhood")
    when 3 then t("admin.stats.budgets.precisions.street")
    when 4 then t("admin.stats.budgets.precisions.building")
    else t("admin.stats.budgets.density_level")
    end
  end

  private

    def stats
      @stats ||= Budget::Stats.new(budget, cache: false)
    end

    def headings_stats
      @headings_stats ||= stats.headings
    end

    def active_geozones
      @active_geozones ||= budget.geozones.where.not(geojson: [nil, ""])
    end
end
