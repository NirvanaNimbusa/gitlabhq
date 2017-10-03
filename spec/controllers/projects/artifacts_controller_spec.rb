require 'spec_helper'

describe Projects::ArtifactsController do
  set(:user) { create(:user) }
  set(:project) { create(:project, :repository) }

  let(:pipeline) do
    create(:ci_pipeline,
            project: project,
            sha: project.commit.sha,
            ref: project.default_branch,
            status: 'success')
  end

  let(:job) { create(:ci_build, :success, :artifacts, pipeline: pipeline) }

  before do
    project.add_developer(user)

    sign_in(user)
  end

  describe 'GET download' do
    it 'sends the artifacts file' do
      expect(controller).to receive(:send_file).with(job.artifacts_file.path, hash_including(disposition: 'attachment')).and_call_original

      get :download, namespace_id: project.namespace, project_id: project, job_id: job
    end
  end

  describe 'GET browse' do
    context 'when the directory exists' do
      it 'renders the browse view' do
        get :browse, namespace_id: project.namespace, project_id: project, job_id: job, path: 'other_artifacts_0.1.2'

        expect(response).to render_template('projects/artifacts/browse')
      end
    end

    context 'when the directory does not exist' do
      it 'responds Not Found' do
        get :browse, namespace_id: project.namespace, project_id: project, job_id: job, path: 'unknown'

        expect(response).to be_not_found
      end
    end
  end

  describe 'GET file' do
    before do
      allow(Gitlab.config.pages).to receive(:enabled).and_return(true)
      allow(Gitlab.config.pages).to receive(:artifacts_server).and_return(true)
    end

    context 'when the file exists' do
      it 'renders the file view' do
        get :file, namespace_id: project.namespace, project_id: project, job_id: job, path: 'ci_artifacts.txt'

        expect(response).to have_http_status(302)
      end
    end

    context 'when the file does not exist' do
      it 'responds Not Found' do
        get :file, namespace_id: project.namespace, project_id: project, job_id: job, path: 'unknown'

        expect(response).to be_not_found
      end
    end
  end

  describe 'GET raw' do
    subject { get(:raw, namespace_id: project.namespace, project_id: project, job_id: job, path: path) }

    context 'when the file exists' do
      let(:path) { 'ci_artifacts.txt' }
      let(:job) { create(:ci_build, :success, :artifacts, pipeline: pipeline, artifacts_file_store: store, artifacts_metadata_store: store) }

      shared_examples 'a valid file' do
        it 'serves the file using workhorse' do
          subject

          expect(send_data).to start_with('artifacts-entry:')

          expect(params.keys).to eq(%w(Archive Entry))
          expect(params['Archive']).to start_with(archive_path)
          # On object storage, the URL can end with a query string
          expect(params['Archive']).to match(/build_artifacts.zip(\?[^?]+)?$/)
          expect(params['Entry']).to eq(Base64.encode64('ci_artifacts.txt'))
        end

        def send_data
          response.headers[Gitlab::Workhorse::SEND_DATA_HEADER]
        end

        def params
          @params ||= begin
            base64_params = send_data.sub(/\Aartifacts\-entry:/, '')
            JSON.parse(Base64.urlsafe_decode64(base64_params))
          end
        end
      end

      context 'when using local file storage' do
        it_behaves_like 'a valid file' do
          let(:store) { ObjectStoreUploader::LOCAL_STORE }
          let(:archive_path) { ArtifactUploader.local_store_path }
        end
      end

      context 'when using remote file storage' do
        before do
          stub_artifacts_object_storage
        end

        it_behaves_like 'a valid file' do
          let(:store) { ObjectStoreUploader::REMOTE_STORE }
          let(:archive_path) { 'https://' }
        end
      end
    end
  end

  describe 'GET latest_succeeded' do
    def params_from_ref(ref = pipeline.ref, job_name = job.name, path = 'browse')
      {
        namespace_id: project.namespace,
        project_id: project,
        ref_name_and_path: File.join(ref, path),
        job: job_name
      }
    end

    context 'cannot find the job' do
      shared_examples 'not found' do
        it { expect(response).to have_http_status(:not_found) }
      end

      context 'has no such ref' do
        before do
          get :latest_succeeded, params_from_ref('TAIL', job.name)
        end

        it_behaves_like 'not found'
      end

      context 'has no such job' do
        before do
          get :latest_succeeded, params_from_ref(pipeline.ref, 'NOBUILD')
        end

        it_behaves_like 'not found'
      end

      context 'has no path' do
        before do
          get :latest_succeeded, params_from_ref(pipeline.sha, job.name, '')
        end

        it_behaves_like 'not found'
      end
    end

    context 'found the job and redirect' do
      shared_examples 'redirect to the job' do
        it 'redirects' do
          path = browse_project_job_artifacts_path(project, job)

          expect(response).to redirect_to(path)
        end
      end

      context 'with regular branch' do
        before do
          pipeline.update(ref: 'master',
                          sha: project.commit('master').sha)

          get :latest_succeeded, params_from_ref('master')
        end

        it_behaves_like 'redirect to the job'
      end

      context 'with branch name containing slash' do
        before do
          pipeline.update(ref: 'improve/awesome',
                          sha: project.commit('improve/awesome').sha)

          get :latest_succeeded, params_from_ref('improve/awesome')
        end

        it_behaves_like 'redirect to the job'
      end

      context 'with branch name and path containing slashes' do
        before do
          pipeline.update(ref: 'improve/awesome',
                          sha: project.commit('improve/awesome').sha)

          get :latest_succeeded, params_from_ref('improve/awesome', job.name, 'file/README.md')
        end

        it 'redirects' do
          path = file_project_job_artifacts_path(project, job, 'README.md')

          expect(response).to redirect_to(path)
        end
      end
    end
  end
end
