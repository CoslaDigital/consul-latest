# app/models/budget/stvresult.rb

class Budget
  class Stvresult
    attr_accessor :budget, :heading, :user

    def initialize(budget, heading, user:)
      @budget = budget
      @heading = heading
      @user = user
      @log_file_name = "stv_voting_#{budget.name}_#{heading.name}.log"

      log_path = Rails.root.join("log", @log_file_name)
      File.open(log_path, "w") {}
    end

    def calculate_stv_winners
      reset_winners

      summary_slug = "stv_results_#{@budget.name}_#{@heading.name}".parameterize
      detail_slug = "stv_details_#{@budget.name}_#{@heading.name}".parameterize
      summary_title = "Election Results: #{@budget.name}"
      detail_title  = "Detailed Election Log: #{@budget.name}"

      seats = heading_seats
      candidates = @heading.investments.where(budget_id: @budget.id, selected: true)
      investment_titles = candidates.pluck(:id, :title).to_h

      ballot_data = get_votes_data
      votes_cast = ballot_data.size

      if seats <= 0 || votes_cast.zero? || candidates.empty?
        write_to_output("<h2>Election Aborted</h2><p>Missing seats, ballots, or candidates.</p>")
        return []
      end

      initial_quota = droop_quota(votes_cast.to_f, seats)
      dynamic_quota_enabled = @budget.respond_to?(:stv_dynamic_quota?) && @budget.stv_dynamic_quota?

      calculator = StvCalculator.new
      result = calculator.calculate(
        ballot_data,
        seats,
        initial_quota,
        investment_titles,
        dynamic_quota_enabled: dynamic_quota_enabled
      )

      write_to_output("✅ STV Calculation Completed. #{result.winners.size} winners found.")

      render_and_attach_reports(result, candidates, votes_cast, initial_quota, investment_titles,
                                summary_title, summary_slug, detail_title, detail_slug,
                                dynamic_quota_enabled)

      update_winning_investments(result.winners)
      result.winners
    end

    private

      def heading_seats
        if @heading.respond_to?(:effective_max_winners)
          @heading.effective_max_winners.to_i
        else
          @heading.max_winners.to_i
        end
      end

      def droop_quota(total_value, seats)
        return 0 if seats <= 0
        (total_value / (seats + 1)).floor + 1
      end

      def render_and_attach_reports(result, candidates, votes_cast, quota, investment_titles,
                                    summary_title, summary_slug, detail_title, detail_slug,
                                    dynamic_quota_enabled)
        summary_html = ApplicationController.render(
          StvSummaryReportComponent.new(
            result: result,
            budget: @budget,
            heading: @heading,
            candidates: candidates,
            votes_cast: votes_cast,
            quota: quota,
            report_title: summary_title,
            detail_page_slug: detail_slug,
            dynamic_quota_enabled: dynamic_quota_enabled
          ),
          layout: false
        )

        detail_html = ApplicationController.render(
          StvDetailReportComponent.new(
            rounds: result.rounds,
            investment_titles: investment_titles,
            dynamic_quota_enabled: dynamic_quota_enabled
          ),
          layout: false
        )

        pdf_html = ApplicationController.render(
          template: "budgets/results/stv_report_pdf",
          layout: "pdf",
          assigns: {
            budget: @budget,
            heading: @heading,
            result: result,
            candidates: candidates,
            votes_cast: votes_cast,
            quota: quota,
            investment_titles: investment_titles
          }
        )

        pdf_file = WickedPdf.new.pdf_from_string(pdf_html)
        document_title = "STV Full Report: #{@heading.name}"

        @heading.documents.where(title: document_title).destroy_all
        @heading.documents.create!(
          title: document_title,
          user: @user,
          attachment: {
            io: StringIO.new(pdf_file),
            filename: "stv_report_#{@budget.slug}_#{@heading.slug}.pdf",
            content_type: "application/pdf"
          }
        )

        update_custom_page(summary_html, summary_title, summary_slug)
        update_custom_page(detail_html, detail_title, detail_slug)
      end

      def get_ballots
        @budget.ballots
      end

      def get_votes_data(ballots = get_ballots)
        ballot_ids = ballots.pluck(:id)

        all_lines = Budget::Ballot::Line
                      .where(ballot_id: ballot_ids, heading_id: @heading.id)
                      .order(:position)
                      .select(:ballot_id, :investment_id)

        lines_by_ballot = all_lines.group_by(&:ballot_id)

        valid_ballots = []
        ballot_ids.each do |id|
          rankings = lines_by_ballot[id]&.map(&:investment_id) || []
          valid_ballots << { rankings: rankings } if rankings.any?
        end

        valid_ballots
      end

      def update_winning_investments(winning_investment_ids)
        ids = winning_investment_ids.to_a
        return if ids.empty?

        Budget::Investment.unscoped.where(id: ids).each do |investment|
          investment.class.without_auditing { investment.update!(winner: true) }
          investment.reload
        end
      end

      def update_custom_page(html_content, page_title, page_slug)
        page = SiteCustomization::Page.find_or_initialize_by(slug: page_slug)
        page.update(status: "published", title: page_title, content: html_content)
      end

      def candidates
        if @heading.investments.selected.respond_to?(:sort_by_votes)
          @heading.investments.selected.sort_by_votes
        else
          @heading.investments.selected.order(:id)
        end
      end

      def reset_winners
        candidates.update_all(winner: false)
        if Budget::Investment.column_names.include?("votes")
          candidates.update_all(votes: 0)
        end
      end

      def write_to_output(message)
        log_path = Rails.root.join("log", @log_file_name)
        File.open(log_path, "a") { |file| file.puts(message) }
      end
  end
end
