RSpec.describe 'Inertia::Request', type: :request do
  describe 'it tests whether a call is an inertia call' do
    subject { response.status }
    before { get inertia_request_test_path, headers: headers }

    context 'it is an inertia call' do
      let(:headers) { {'X-Inertia' => true} }

      it { is_expected.to eq 202 }
    end

    context 'it is not an inertia call' do
      let(:headers) { Hash.new }

      it { is_expected.to eq 200 }
    end
  end

  describe 'it tests whether a call is a partial inertia call' do
    subject { response.status }
    before { get inertia_partial_request_test_path, headers: headers }

    context 'it is a partial inertia call' do
      let(:headers) { { 'X-Inertia' => true, 'X-Inertia-Partial-Data' => 'foo,bar,baz' } }

      it { is_expected.to eq 202 }
    end

    context 'it is not a partial inertia call' do
      let(:headers) { { 'X-Inertia' => true } }

      it { is_expected.to eq 200 }
    end
  end

  describe 'it tests error 404' do
    subject { response.status }
    before { get '/error_404', headers: headers }

    context 'it is a inertia call' do
      let(:headers) { { 'X-Inertia' => true } }

      it { is_expected.to eq 404 }
    end

    context 'it is not a inertia call' do
      let(:headers) { {} }

      it { is_expected.to eq 404 }
    end
  end

  describe 'it tests error 500' do
    subject { response.status }
    before { get '/error_500', headers: headers }

    context 'it is a inertia call' do
      let(:headers) { { 'X-Inertia' => true } }

      it { is_expected.to eq 500 }
    end

    context 'it is not a inertia call' do
      let(:headers) { {} }

      it { is_expected.to eq 500 }
    end
  end

  describe 'it tests media_type of the response' do
    subject { response.media_type }
    before { get content_type_test_path, headers: headers }

    context 'it is an inertia call' do
      let(:headers) { {'X-Inertia' => true} }

      it { is_expected.to eq 'application/json' }
    end

    context 'it is not an inertia call' do
      let(:headers) { Hash.new }

      it { is_expected.to eq 'text/html' }
    end

    context 'it is an XML request' do
      let(:headers) { { accept: 'application/xml' } }

      it { is_expected.to eq 'application/xml' }
    end
  end

  describe 'it tests redirecting with responders gem' do
    subject { response.status }
    before { post redirect_with_responders_path }

    it { is_expected.to eq 302 }
  end

  describe 'CSRF' do
    describe 'it sets the XSRF-TOKEN in the cookies' do
      subject { response.cookies }
      before do
        with_forgery_protection do
          get inertia_request_test_path, headers: headers
        end
      end

      context 'it is not an inertia call' do
        let(:headers) { Hash.new }
        it { is_expected.to include('XSRF-TOKEN') }
      end

      context 'it is an inertia call' do
        let(:headers){ { 'X-Inertia' => true } }
        it { is_expected.not_to include('XSRF-TOKEN') }
      end
    end

    describe 'copying an X-XSRF-Token header (like Axios sends by default) into the X-CSRF-Token header (that Rails looks for by default)' do
      subject { request.headers['X-CSRF-Token'] }
      before { get inertia_request_test_path, headers: headers }

      context 'it is an inertia call' do
        let(:headers) {{ 'X-Inertia' => true, 'X-XSRF-Token' => 'foo' }}
        it { is_expected.to eq 'foo' }
      end

      context 'it is not an inertia call' do
        let(:headers) { { 'X-XSRF-Token' => 'foo' } }
        it { is_expected.to be_nil }
      end
    end
  end
end
