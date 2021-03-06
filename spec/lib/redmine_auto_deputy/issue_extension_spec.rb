require 'spec_helper'

RSpec.describe RedmineAutoDeputy::IssueExtension do

  before(:each) do
    Tracker.delete_all
    IssueStatus.delete_all
    IssuePriority.delete_all
  end

  specify { expect(Issue.included_modules).to include(described_class)}

  describe 'check_assigned_user_availability on before_save if assigned_to_id_changed?' do
    let(:filter) { Issue._save_callbacks.select {|c| c.kind ==  :before && c.filter == :check_assigned_user_availability }.first }
    specify do
      expect(filter.instance_variable_get('@if')).to match_array([:recheck_availability_required?])
    end
  end

  describe '#check_assigned_user_availability' do

    context 'assigned_to.nil?' do
      let(:issue) { build_stubbed(:issue) }
      specify do
        expect(issue.send(:check_assigned_user_availability)).to be(nil)
        expect(issue.assigned_to).to be(nil)
      end
    end

    context 'assigned_to is not a User' do
      let(:group) { Group.new }
      let(:issue) { build_stubbed(:issue, assigned_to: group) }
      specify do
        expect(issue.send(:check_assigned_user_availability)).to be(nil)
        expect(issue.assigned_to).to eq(group)
      end
    end

    context 'assigned_to User.current' do
      let(:issue) { build_stubbed(:issue, assigned_to: user) }
      let(:user)  { build_stubbed(:user)}

      before { expect(User).to receive(:current).and_return(user) }

      specify do
        expect(issue.send(:check_assigned_user_availability)).to be(nil)
      end
    end

    context 'uses current date if no due_date date is assigned' do
      let(:issue) { build_stubbed(:issue, assigned_to: user) }
      let(:user)  { build_stubbed(:user)}

      before { expect(user).to receive(:available_at?).with(Time.now.to_date).and_return true }
      specify { expect(issue.send(:check_assigned_user_availability)).to be(true) }
    end

    context 'uses current date if due_date is in the past' do
      let(:issue) { build_stubbed(:issue, assigned_to: user, due_date: Time.now - 3.days) }
      let(:user)  { build_stubbed(:user)}

      before { expect(user).to receive(:available_at?).with(Time.now.to_date).and_return true }
      specify { expect(issue.send(:check_assigned_user_availability)).to be(true) }
    end

    context 'uses due_to date to find deputy' do
      let(:date)    { Time.now.to_date+1.week }
      let(:issue)   { build(:issue, assigned_to: user, start_date: date, project: project) }
      let(:user)    { build_stubbed(:user)}
      let(:deputy)  { build_stubbed(:user, firstname: 'Deputy')}

      let(:user_deputy) { build_stubbed(:user_deputy, deputy: deputy)}
      let(:project)     { build_stubbed(:project) }

      let(:journal) { Journal.new(:journalized => issue, :user => user, :notes => nil) }

      before do
        expect(user).to receive(:available_at?).with(date).and_return false
        expect(project).to receive(:possible_project_id_for_deputies).with(user).and_return(1)
        expect(user).to receive(:find_deputy).with(project_id: 1, date: date).and_return(user_deputy)

        expect(issue).to receive(:add_watcher).with(user)
      end

      context 'journal is present' do
        before do
          expect(issue).to receive(:current_journal).and_return(journal).exactly(2).times
          expect(journal).to receive('notes=').with(I18n.t('issue_assigned_to_changed', new_name: deputy.name, original_name: user.name) )
        end

        specify do
          expect(issue.send(:check_assigned_user_availability)).to eq(true)
          expect(issue.assigned_to).to eq(deputy)
        end
      end

      context 'journal is not present' do
        before do
          expect(issue).to receive(:init_journal).and_call_original
        end

        specify do
          expect(issue.send(:check_assigned_user_availability)).to eq(true)
          expect(issue.assigned_to).to eq(deputy)
        end
      end
    end

    context 'fails to find deputy' do
      let(:date)    { Time.now.to_date+1.week }
      let(:project)     { build_stubbed(:project) }
      let(:issue) { build_stubbed(:issue, assigned_to: user, project_id: 1, start_date: date, project: project) }
      let(:user)  { build_stubbed(:user, firstname: 'Max', lastname: 'Muster', unavailable_from: date-1.days, unavailable_to: date+1.days)}

      # Mocking I18n, for some reasons, locales from plugin are not loaded
      let(:i18n_error_string) { 'Error Happend' }

      before do
        expect(user).to receive(:available_at?).with(date).and_return false
        expect(project).to receive(:possible_project_id_for_deputies).with(user).and_return(1)
        expect(user).to receive(:find_deputy).with(project_id: 1, date: date).and_return(nil)
        expect(I18n).to receive(:t).with('activerecord.errors.issue.cant_be_assigned_due_to_unavailability', user_name: user.name, date: date.to_s, from: user.unavailable_from.to_s, to: user.unavailable_to.to_s).and_return(i18n_error_string)
      end

      specify do
        expect(issue.send(:check_assigned_user_availability)).to eq(false)
        expect(issue.errors[:assigned_to]).to include(i18n_error_string)
      end

    end

    context 'change start_date' do

      Issue.skip_callback(:create, :after, :send_notification)

      let(:user)    { create(:user)}
      let!(:project) { create(:project, identifier: "mytest#{rand(50)}") }
      let(:issue)   { create(:issue, :with_issue_data, subject: 'somethings wrong', assigned_to: user, start_date: Date.new(2016,1,1), project: project) }

      before do
        allow(issue).to receive(:assigned_to).and_return(user)
        expect(user).to receive(:available_at?).with(Date.tomorrow)
      end

      specify { issue.update_attributes(start_date: Date.tomorrow) }

    end

    context 'change assigned to' do

      Issue.skip_callback(:create, :after, :send_notification)

      let(:user)    { create(:user)}
      let(:user_new)    { create(:user)}
      let!(:project) { create(:project, identifier: "mytest#{rand(50)}") }
      let(:issue)   { create(:issue, :with_issue_data, subject: 'somethings wrong', assigned_to: user, start_date: Date.tomorrow, project: project) }

      before do
        expect(user_new).to receive(:available_at?).with(Date.tomorrow)
      end

      specify { issue.update_attributes(assigned_to: user_new) }

    end

    context 'only one day unavailable' do
      let(:user)  { build_stubbed(:user, unavailable_from: (Time.now+1.day).to_date, unavailable_to: (Time.now+1.day).to_date) }
      let(:issue) { build_stubbed(:issue, assigned_to: user, start_date: Time.now+1.day) }

      before { expect(issue).to receive_message_chain(:project, :possible_project_id_for_deputies).and_return([1]) }

      specify do
        expect(issue.send(:check_assigned_user_availability)).to be(false)
      end
    end

    context 'Exception handling' do
      let(:user) { build_stubbed(:user) }
      let(:issue) { build_stubbed(:issue, assigned_to: user, id: 1) }
      let(:error) { Exception.new(message: 'Bad thing happend') }

      before do
        expect(user).to receive(:available_at?).and_raise(error)
        expect(error).to receive(:backtrace).and_return(['line 1', 'line 2']).at_least(:once)
        expect(Rails.logger).to receive(:error).with("Failed to check_assigned_user_availability for Issue #1: #{error.message}")
        expect(Rails.logger).to receive(:error).with(['line 1', 'line 2'].join("\n"))
      end

      specify do
        expect{ issue.send(:check_assigned_user_availability) }.not_to raise_error
        expect(issue.assigned_to).to eq(user)
      end
    end

  end

end