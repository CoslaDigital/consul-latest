class Budget
  class Stvresult
    attr_accessor :budget, :heading, :user

    def initialize(budget, heading, user:)
      @budget = budget
      @heading = heading
      @user = user
      @log_file_name = "stv_voting_#{budget.name}_#{heading.name}.log"

      # Initialize/clear the log file
      log_path = Rails.root.join('log', @log_file_name)
      File.open(log_path, 'w') {}
    end

    def droop_quota(total_value, seats)
      (total_value / (seats + 1)).floor + 1
    end

    def calculate_stv_winners
      reset_winners

      summary_slug = "stv_results_#{@budget.name}_#{@heading.name}".parameterize
      detail_slug = "stv_details_#{@budget.name}_#{@heading.name}".parameterize
      summary_title = "Election Results: #{@budget.name}"
      detail_title  = "Detailed Election Log: #{@budget.name}"

      seats = @heading.respond_to?(:effective_max_winners) ? @heading.effective_max_winners.to_i : @heading.max_winners.to_i
      candidates = @heading.investments.where(budget_id: @budget.id, selected: true)
      investment_titles = candidates.pluck(:id, :title).to_h

      # Uses your proven extraction method
      ballot_data = get_votes_data
      votes_cast = ballot_data.size

      if seats <= 0 || votes_cast == 0 || candidates.empty?
        write_to_output("<h2>Election Aborted</h2><p>Missing seats, ballots, or candidates.</p>")
        return []
      end

      initial_quota = droop_quota(votes_cast.to_f, seats)
      dynamic_quota_enabled = @budget.respond_to?(:stv_dynamic_quota?) && @budget.stv_dynamic_quota?

      # 1. Wire directly into your external StvCalculator class
      calculator = StvCalculator.new
      result = calculator.calculate(
        ballot_data,
        seats,
        initial_quota,
        investment_titles,
        dynamic_quota_enabled: dynamic_quota_enabled
      )

      write_to_output("✅ STV Calculation Completed. #{result.winners.size} winners found.")

      # 2. Render Reports
      summary_html_report = ApplicationController.render(
        StvSummaryReportComponent.new(
          result: result,
          budget: @budget,
          heading: @heading,
          candidates: candidates,
          votes_cast: votes_cast,
          quota: initial_quota,
          report_title: summary_title,
          detail_page_slug: detail_slug,
          dynamic_quota_enabled: dynamic_quota_enabled
        ),
        layout: false
      )

      detailed_html_report = ApplicationController.render(
        StvDetailReportComponent.new(
          rounds: result.rounds,
          investment_titles: investment_titles,
          dynamic_quota_enabled: dynamic_quota_enabled
        ),
        layout: false
      )

      pdf_html_content = ApplicationController.render(
        template: "budgets/results/stv_report_pdf",
        layout: "pdf",
        assigns: {
          budget: @budget,
          heading: @heading,
          result: result,
          candidates: candidates,
          votes_cast: votes_cast,
          quota: initial_quota,
          investment_titles: investment_titles
        }
      )

      pdf_file = WickedPdf.new.pdf_from_string(pdf_html_content)
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

      update_winning_investments(result.winners)
      update_custom_page(summary_html_report, summary_title, summary_slug)
      update_custom_page(detailed_html_report, detail_title, detail_slug)

      result.winners

    rescue StandardError => e
      write_to_output("❌ CRASH ERROR: #{e.message}\n#{e.backtrace.join("\n")}")
      raise e
    end

    private

      def get_ballots
        @budget.ballots
      end

      # Your proven database extraction method from Reference 2
      def get_votes_data(ballots = get_ballots)
        ballot_ids = ballots.pluck(:id)

        all_lines = Budget::Ballot::Line.where(ballot_id: ballot_ids, heading_id: @heading.id)
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
        investments = Budget::Investment.unscoped.where(id: ids)
        investments.each do |investment|
          investment.class.without_auditing { investment.update!(winner: true) }
          investment.reload
        end
      end

      def update_custom_page(html_content, page_title, page_slug)
        page = SiteCustomization::Page.find_or_initialize_by(slug: page_slug)
        page.update(status: 'published', title: page_title, content: html_content)
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
        if Budget::Investment.column_names.include?('votes')
          candidates.update_all(votes: 0)
        end
      end

      def write_to_output(message)
        log_path = Rails.root.join('log', @log_file_name)
        File.open(log_path, 'a') { |file| file.puts(message) }
      end
  end
end
