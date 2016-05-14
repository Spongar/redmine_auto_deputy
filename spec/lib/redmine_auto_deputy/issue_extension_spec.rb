require 'spec_helper'

RSpec.describe RedmineAutoDeputy::IssueExtension do

  specify { expect(Issue.included_modules).to include(described_class)}

  describe 'check_assigned_user_availability on before_save if assigned_to_id_changed?' do
    let(:filter) { Issue._save_callbacks.select {|c| c.kind ==  :before && c.filter == :check_assigned_user_availability }.first }
    specify do
      expect(filter.instance_variable_get('@if')).to match_array([:assigned_to_id_changed?])
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

    context 'uses current date if no due_to date is assigned' do
      let(:issue) { build_stubbed(:issue, assigned_to: user) }
      let(:user)  { build_stubbed(:user)}

      before { expect(user).to receive(:available_at?).with(Time.now.to_date).and_return true }
      specify { expect(issue.send(:check_assigned_user_availability)).to be(true) }
    end

    context 'uses due_to date to find deputy' do
      let(:date)    { Time.now.to_date+1.week }
      let(:issue)   { build(:issue, assigned_to: user, due_date: date, project_id: 1) }
      let(:user)    { build_stubbed(:user)}
      let(:deputy)  { build_stubbed(:user, firstname: 'Deputy')}

      let(:user_deputy) { build_stubbed(:user_deputy, deputy: deputy)}

      before do
        # need to mock 'project_id' getter, as redmine does not allow to set the id directly
        expect(issue).to receive(:project_id).and_return(1)
        expect(user).to receive(:available_at?).with(date).and_return false
        expect(user).to receive(:find_deputy).with(project_id: 1, date: date).and_return(user_deputy)
        expect(issue).to receive_message_chain(:current_journal, 'notes=').with(I18n.t('issue_assigned_to_changed', new_name: deputy.name, original_name: user.name) )
      end

      specify do
        expect(issue.send(:check_assigned_user_availability)).to eq(true)
        expect(issue.assigned_to).to eq(deputy)
      end
    end

    context 'fails to find deputy' do
      let(:date)    { Time.now.to_date+1.week }
      let(:issue) { build_stubbed(:issue, assigned_to: user, project_id: 1, due_date: date) }
      let(:user)  { build_stubbed(:user, firstname: 'Max', lastname: 'Muster')}

      before do
        # need to mock 'project_id' getter, as redmine does not allow to set the id directly
        expect(issue).to receive(:project_id).and_return(1)
        expect(user).to receive(:available_at?).with(date).and_return false
        expect(user).to receive(:find_deputy).with(project_id: 1, date: date).and_return(nil)
      end

      specify do
        expect(issue.send(:check_assigned_user_availability)).to eq(false)
        expect(issue.errors[:assigned_to]).to include(I18n.t('activerecord.errors.issue.cant_be_assigned_due_to_unavailability', user_name: user.name, date: date.to_s))
      end

    end

  end

end