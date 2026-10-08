class Budget
  class Stvresult
    attr_accessor :budget, :heading, :current_investment

    def initialize(budget, heading, user:)
      @budget = budget
      @heading = heading
      @user = user
      @log_file_name = "stv_voting_#{budget.name}_#{heading.name}.log"

      # Initialize/clear the log file
      log_path = Rails.root.join('log', @log_file_name)
      File.open(log_path, 'w') {}
    end

    def calculate_stv_winners
      reset_winners

      summary_slug = "stv_results_#{@budget.name}_#{@heading.name}".parameterize
      detail_slug = "stv_details_#{@budget.name}_#{@heading.name}".parameterize
      summary_title = "Election Results: #{@budget.name}"
      detail_title  = "Detailed Election Log: #{@budget.name}"

      # Safely extract seats (guards against custom method names)
      seats = if @heading.respond_to?(:effective_max_winners)
                @heading.effective_max_winners.to_i
              else
                @heading.max_winners.to_i
              end

      candidates = @heading.investments.where(budget_id: @budget.id, selected: true)
      investment_titles = candidates.pluck(:id, :title).to_h

      ballot_data = get_votes_data
      votes_cast = ballot_data.size

      if seats <= 0 || votes_cast == 0 || candidates.empty?
        write_to_output("<h2>Election Aborted</h2><p>Missing seats, ballots, or candidates.</p>")
        return []
      end

      # 1. Wire directly into the external StvCalculator class!
      initial_quota = (votes_cast.to_f / (seats + 1)).floor + 1
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
          filename: "stv_report_#{@budget.id}_#{@heading.id}.pdf",
          content_type: "application/pdf"
        }
      )

      update_winning_investments(result.winners)
      update_custom_page(summary_html_report, summary_title, summary_slug)
      update_custom_page(detailed_html_report, detail_title, detail_slug)

      result.winners

    rescue StandardError => e
      # If it EVER crashes again, the log file will tell you exactly why instead of staying blank
      write_to_output("❌ CRASH ERROR: #{e.message}\n#{e.backtrace.join("\n")}")
      raise e
    end

    private

      def get_votes_data
        valid_ballots = []

        # 3. Use ActiveRecord associations safely instead of hardcoded column names
        @budget.ballots.includes(lines: :investment).find_each do |ballot|

          # Filter lines by heading safely
          heading_lines = ballot.lines.select do |line|
            h_id = line.respond_to?(:budget_heading_id) ? line.budget_heading_id : line.heading_id
            h_id == @heading.id
          end

          next if heading_lines.empty?

          # Handle the 'position' column dynamically
          heading_lines.sort_by! { |l| l.respond_to?(:position) ? l.position.to_i : l.preference.to_i }

          # Pluck the IDs
          rankings = heading_lines.map { |line| line.investment.id }
          valid_ballots << { rankings: rankings }
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
        # Prevents crashing if the physical 'votes' column isn't present
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
