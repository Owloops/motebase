const STORAGE_KEY_TOKEN = 'motebase_admin_token';
const STORAGE_KEY_USER = 'motebase_admin_user';
const RECORDS_PER_PAGE = 20;
const COLLECTIONS_PER_PAGE = 12;
const MAX_VISIBLE_FIELDS = 5;

const FIELD_ICONS = {
  id: '<svg viewBox="0 0 24 24"><path d="M12 2a5 5 0 0 1 5 5v3H7V7a5 5 0 0 1 5-5z"/><rect x="3" y="10" width="18" height="12" rx="2"/></svg>',
  text: '<svg viewBox="0 0 24 24"><path d="M4 7V4h16v3"/><path d="M9 20h6"/><path d="M12 4v16"/></svg>',
  email: '<svg viewBox="0 0 24 24"><rect x="2" y="4" width="20" height="16" rx="2"/><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"/></svg>',
  url: '<svg viewBox="0 0 24 24"><path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/></svg>',
  number: '<svg viewBox="0 0 24 24"><path d="M4 9h16"/><path d="M4 15h16"/><path d="M10 3 8 21"/><path d="M16 3 14 21"/></svg>',
  boolean: '<svg viewBox="0 0 24 24"><rect x="1" y="5" width="22" height="14" rx="7"/><circle cx="16" cy="12" r="3"/></svg>',
  json: '<svg viewBox="0 0 24 24"><path d="M8 3H7a2 2 0 0 0-2 2v5a2 2 0 0 1-2 2 2 2 0 0 1 2 2v5c0 1.1.9 2 2 2h1"/><path d="M16 3h1a2 2 0 0 1 2 2v5a2 2 0 0 0 2 2 2 2 0 0 0-2 2v5a2 2 0 0 1-2 2h-1"/></svg>',
  file: '<svg viewBox="0 0 24 24"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>',
  relation: '<svg viewBox="0 0 24 24"><path d="M16 3h5v5"/><path d="M8 3H3v5"/><path d="M21 3l-9 9"/><path d="M16 21h5v-5"/><path d="M8 21H3v-5"/><path d="M21 21l-9-9"/></svg>',
  date: '<svg viewBox="0 0 24 24"><rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>',
  select: '<svg viewBox="0 0 24 24"><path d="m6 9 6 6 6-6"/></svg>'
};
FIELD_ICONS.string = FIELD_ICONS.text;
FIELD_ICONS.bool = FIELD_ICONS.boolean;

const AVAILABLE_FIELD_TYPES = [
  { type: 'text', label: 'Text', icon: FIELD_ICONS.text },
  { type: 'number', label: 'Number', icon: FIELD_ICONS.number },
  { type: 'boolean', label: 'Boolean', icon: FIELD_ICONS.boolean },
  { type: 'email', label: 'Email', icon: FIELD_ICONS.email },
  { type: 'url', label: 'URL', icon: FIELD_ICONS.url },
  { type: 'date', label: 'Date', icon: FIELD_ICONS.date },
  { type: 'json', label: 'JSON', icon: FIELD_ICONS.json },
  { type: 'file', label: 'File', icon: FIELD_ICONS.file },
  { type: 'relation', label: 'Relation', icon: FIELD_ICONS.relation },
  { type: 'select', label: 'Select', icon: FIELD_ICONS.select }
];

function adminApp() {
  return {
    authToken: localStorage.getItem(STORAGE_KEY_TOKEN),
    currentUser: JSON.parse(localStorage.getItem(STORAGE_KEY_USER) || 'null'),
    loginForm: { email: '', password: '' },
    isLoading: false,
    currentRoute: 'dashboard',
    routeParams: {},
    collections: [],
    records: [],
    recordFormData: {},
    originalRecordData: {},
    fileUploads: {},
    filePreviews: {},
    filesToRemove: [],
    passwordField: '',
    passwordConfirmField: '',
    currentPage: 1,
    totalPages: 1,
    totalItems: 0,
    filterQuery: '',
    sortField: '',
    sortDirection: '',
    collectionSearchQuery: '',
    collectionsPage: 1,
    selectedRecordIds: [],
    settingsData: null,
    settingsChanged: false,
    logsData: { items: [], totalItems: 0, totalPages: 1 },
    logsStats: null,
    logsPage: 1,
    logsFilter: { status: '', method: '', path: '' },
    jobsData: { items: [], totalItems: 0, totalPages: 1 },
    jobsStats: null,
    jobsPage: 1,
    jobsFilter: { status: '', name: '' },
    cronsData: { items: [] },
    showCollectionModal: false,
    collectionModalTab: 'fields',
    collectionModalError: '',
    editingCollection: null,
    showFieldTypePicker: false,
    collectionForm: {
      name: '',
      type: 'base',
      fields: [],
      listRule: '',
      viewRule: '',
      createRule: '',
      updateRule: '',
      deleteRule: ''
    },
    availableFieldTypes: AVAILABLE_FIELD_TYPES,
    toasts: [],
    toastIdCounter: 0,

    async init() {
      if (this._initialized) return;
      this._initialized = true;

      if (this.authToken) {
        await this.loadCollections();
      }
      this.parseRoute();
      window.addEventListener('hashchange', (e) => {
        if (this.hasUnsavedChanges() && this.currentRoute === 'record') {
          if (!confirm('You have unsaved changes. Are you sure you want to leave?')) {
            e.preventDefault();
            history.pushState(null, '', e.oldURL);
            return;
          }
        }
        this.parseRoute();
      });
      window.addEventListener('beforeunload', (e) => {
        if (this.hasUnsavedChanges() && this.currentRoute === 'record') {
          e.preventDefault();
        }
      });
    },

    parseRoute() {
      const hash = window.location.hash.slice(1) || '/';
      const segments = hash.split('/').filter(Boolean);

      if (segments.length === 0) {
        this.currentRoute = 'dashboard';
        this.routeParams = {};
      } else if (segments[0] === 'collections' && segments[1]) {
        const collectionName = segments[1];
        const collectionExists = this.collections.some(c => c.name === collectionName);
        if (!collectionExists) {
          this.showToast(`Collection "${collectionName}" not found`, 'error');
          window.location.hash = '/';
          return;
        }
        this.currentRoute = 'collection';
        this.routeParams = { collectionName };
        this.currentPage = 1;
        this.filterQuery = '';
        this.sortField = '';
        this.sortDirection = '';
        this.loadRecords();
      } else if (segments[0] === 'records' && segments[1] && segments[2]) {
        const collectionName = segments[1];
        const collectionExists = this.collections.some(c => c.name === collectionName);
        if (!collectionExists) {
          this.showToast(`Collection "${collectionName}" not found`, 'error');
          window.location.hash = '/';
          return;
        }
        this.currentRoute = 'record';
        this.routeParams = {
          collectionName,
          recordId: segments[2]
        };
        this.loadRecordForEdit();
      } else if (segments[0] === 'settings') {
        this.currentRoute = 'settings';
        this.routeParams = {};
        this.loadSettings();
      } else if (segments[0] === 'logs') {
        this.currentRoute = 'logs';
        this.routeParams = {};
        this.logsPage = 1;
        this.loadLogs();
        this.loadLogsStats();
      } else if (segments[0] === 'jobs') {
        this.currentRoute = 'jobs';
        this.routeParams = {};
        this.jobsPage = 1;
        this.loadJobs();
        this.loadJobsStats();
      } else if (segments[0] === 'crons') {
        this.currentRoute = 'crons';
        this.routeParams = {};
        this.loadCrons();
      } else if (segments[0] === 'login') {
        this.currentRoute = 'dashboard';
        if (this.authToken) {
          window.location.hash = '/';
        }
      } else {
        this.currentRoute = 'dashboard';
      }
    },

    navigateTo(path) {
      window.location.hash = path;
    },

    navigateBack() {
      const collectionName = this.routeParams.collectionName;
      if (collectionName) {
        window.location.hash = `/collections/${collectionName}`;
      } else {
        window.location.hash = '/';
      }
    },

    async apiRequest(method, path, body = null) {
      const headers = {
        'Content-Type': 'application/json'
      };

      if (this.authToken) {
        headers['Authorization'] = `Bearer ${this.authToken}`;
      }

      const options = { method, headers };

      if (body !== null) {
        options.body = JSON.stringify(body);
      }

      const response = await fetch(`/api${path}`, options);

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({}));
        throw new Error(errorData.error || errorData.message || `Request failed with status ${response.status}`);
      }

      if (response.status === 204) {
        return null;
      }

      return response.json();
    },

    async apiRequestMultipart(method, path, formData) {
      const headers = {};

      if (this.authToken) {
        headers['Authorization'] = `Bearer ${this.authToken}`;
      }

      const response = await fetch(`/api${path}`, {
        method,
        headers,
        body: formData
      });

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({}));
        throw new Error(errorData.error || errorData.message || `Request failed with status ${response.status}`);
      }

      return response.json();
    },

    async handleLogin() {
      this.isLoading = true;

      try {
        const data = await this.apiRequest('POST', '/auth/login', {
          email: this.loginForm.email,
          password: this.loginForm.password
        });

        this.authToken = data.token;
        this.currentUser = data.user;

        localStorage.setItem(STORAGE_KEY_TOKEN, data.token);
        localStorage.setItem(STORAGE_KEY_USER, JSON.stringify(data.user));

        this.loginForm = { email: '', password: '' };

        await this.loadCollections();
        window.location.hash = '/';
      } catch (error) {
        this.showToast(error.message, 'error');
      } finally {
        this.isLoading = false;
      }
    },

    handleLogout() {
      this.authToken = null;
      this.currentUser = null;
      this.collections = [];
      this.records = [];

      localStorage.removeItem(STORAGE_KEY_TOKEN);
      localStorage.removeItem(STORAGE_KEY_USER);

      window.location.hash = '/';
    },

    async loadCollections() {
      this.isLoading = true;

      try {
        const data = await this.apiRequest('GET', '/collections');
        this.collections = Array.isArray(data.items) ? data.items : (Array.isArray(data) ? data : []);
      } catch (error) {
        this.showToast(error.message, 'error');
        this.collections = [];
      } finally {
        this.isLoading = false;
      }
    },

    async loadRecords() {
      this.isLoading = true;
      this.selectedRecordIds = [];

      try {
        const collectionName = this.routeParams.collectionName;
        let path = `/collections/${collectionName}/records?page=${this.currentPage}&perPage=${RECORDS_PER_PAGE}`;

        if (this.filterQuery) {
          path += `&filter=${encodeURIComponent(this.filterQuery)}`;
        }

        if (this.sortField) {
          const sortParam = this.sortDirection === 'desc' ? `-${this.sortField}` : this.sortField;
          path += `&sort=${encodeURIComponent(sortParam)}`;
        }

        const data = await this.apiRequest('GET', path);

        this.records = data.items || [];
        this.totalPages = data.totalPages || 1;
        this.totalItems = data.totalItems || this.records.length;
      } catch (error) {
        this.showToast(error.message, 'error');
        this.records = [];
      } finally {
        this.isLoading = false;
      }
    },

    async loadRecordForEdit() {
      const recordId = this.routeParams.recordId;

      this.passwordField = '';
      this.passwordConfirmField = '';

      this.fileUploads = {};
      this.filePreviews = {};
      this.filesToRemove = [];

      if (recordId === 'new') {
        this.recordFormData = {};
        this.originalRecordData = {};
        return;
      }

      this.isLoading = true;

      try {
        const collectionName = this.routeParams.collectionName;
        const data = await this.apiRequest('GET', `/collections/${collectionName}/records/${recordId}`);

        this.recordFormData = { ...data };

        delete this.recordFormData.id;
        delete this.recordFormData.created_at;
        delete this.recordFormData.updated_at;

        this.originalRecordData = JSON.parse(JSON.stringify(this.recordFormData));
      } catch (error) {
        this.showToast(error.message, 'error');
      } finally {
        this.isLoading = false;
      }
    },

    handleCreateRecord() {
      const collectionName = this.routeParams.collectionName;
      window.location.hash = `/records/${collectionName}/new`;
    },

    async handleSaveRecord() {
      this.isLoading = true;

      if (this.isAuthCollection && this.passwordField) {
        if (!this.passwordsMatch) {
          this.showToast('Passwords do not match', 'error');
          this.isLoading = false;
          return;
        }
      }

      try {
        const collectionName = this.routeParams.collectionName;
        const recordId = this.routeParams.recordId;
        const hasFileUploads = Object.keys(this.fileUploads).length > 0;

        const dataToSend = { ...this.recordFormData };
        if (this.isAuthCollection && this.passwordField) {
          dataToSend.password = this.passwordField;
        }

        if (hasFileUploads) {
          const formData = new FormData();

          for (const [fieldName, value] of Object.entries(dataToSend)) {
            if (value !== null && value !== undefined) {
              formData.append(fieldName, value);
            }
          }

          for (const [fieldName, file] of Object.entries(this.fileUploads)) {
            formData.append(fieldName, file);
          }

          if (recordId === 'new') {
            await this.apiRequestMultipart('POST', `/collections/${collectionName}/records`, formData);
          } else {
            await this.apiRequestMultipart('PATCH', `/collections/${collectionName}/records/${recordId}`, formData);
          }
        } else {
          if (recordId === 'new') {
            await this.apiRequest('POST', `/collections/${collectionName}/records`, dataToSend);
          } else {
            await this.apiRequest('PATCH', `/collections/${collectionName}/records/${recordId}`, dataToSend);
          }
        }

        this.originalRecordData = JSON.parse(JSON.stringify(this.recordFormData));
        this.fileUploads = {};
        this.filePreviews = {};
        this.passwordField = '';
        this.passwordConfirmField = '';

        window.location.hash = `/collections/${collectionName}`;
      } catch (error) {
        this.showToast(error.message, 'error');
      } finally {
        this.isLoading = false;
      }
    },

    async handleDeleteRecord(recordId) {
      if (!confirm('Are you sure you want to delete this record?')) {
        return;
      }

      try {
        const collectionName = this.routeParams.collectionName;
        await this.apiRequest('DELETE', `/collections/${collectionName}/records/${recordId}`);
        await this.loadRecords();
      } catch (error) {
        this.showToast(error.message, 'error');
      }
    },

    toggleRecordSelection(recordId) {
      const index = this.selectedRecordIds.indexOf(recordId);
      if (index === -1) {
        this.selectedRecordIds.push(recordId);
      } else {
        this.selectedRecordIds.splice(index, 1);
      }
    },

    isRecordSelected(recordId) {
      return this.selectedRecordIds.includes(recordId);
    },

    get allRecordsSelected() {
      return this.records.length > 0 && this.selectedRecordIds.length === this.records.length;
    },

    get someRecordsSelected() {
      return this.selectedRecordIds.length > 0 && this.selectedRecordIds.length < this.records.length;
    },

    toggleSelectAll() {
      if (this.allRecordsSelected) {
        this.selectedRecordIds = [];
      } else {
        this.selectedRecordIds = this.records.map(r => r.id);
      }
    },

    clearSelection() {
      this.selectedRecordIds = [];
    },

    async handleBulkDelete() {
      const count = this.selectedRecordIds.length;
      if (count === 0) return;

      if (!confirm(`Are you sure you want to delete ${count} record${count > 1 ? 's' : ''}? This cannot be undone.`)) {
        return;
      }

      this.isLoading = true;
      
      try {
        const collectionName = this.routeParams.collectionName;

        for (const recordId of this.selectedRecordIds) {
          await this.apiRequest('DELETE', `/collections/${collectionName}/records/${recordId}`);
        }

        this.selectedRecordIds = [];
        await this.loadRecords();
      } catch (error) {
        this.showToast(error.message, 'error');
      } finally {
        this.isLoading = false;
      }
    },

    async loadSettings() {
      this.isLoading = true;
      this.settingsChanged = false;

      try {
        this.settingsData = await this.apiRequest('GET', '/settings');
      } catch (error) {
        this.showToast(error.message, 'error');
      } finally {
        this.isLoading = false;
      }
    },

    markSettingsChanged() {
      this.settingsChanged = true;
    },

    async handleSaveSettings() {
      this.isLoading = true;

      try {
        const result = await this.apiRequest('PATCH', '/settings', this.settingsData.settings);
        this.settingsData.settings = result.settings;
        this.settingsChanged = false;
        this.showToast('Settings saved', 'success');
      } catch (error) {
        this.showToast(error.message, 'error');
      } finally {
        this.isLoading = false;
      }
    },

    async loadLogs() {
      this.isLoading = true;
      
      try {
        let path = `/logs?page=${this.logsPage}&perPage=${RECORDS_PER_PAGE}`;

        if (this.logsFilter.status) {
          path += `&status=${this.logsFilter.status}`;
        }
        if (this.logsFilter.method) {
          path += `&method=${this.logsFilter.method}`;
        }
        if (this.logsFilter.path) {
          path += `&path=${encodeURIComponent(this.logsFilter.path)}`;
        }

        this.logsData = await this.apiRequest('GET', path);
      } catch (error) {
        this.showToast(error.message, 'error');
        this.logsData = { items: [], totalItems: 0, totalPages: 1 };
      } finally {
        this.isLoading = false;
      }
    },

    async loadLogsStats() {
      try {
        this.logsStats = await this.apiRequest('GET', '/logs/stats');
      } catch (error) {
        console.error('Failed to load logs stats:', error);
      }
    },

    async handleClearLogs() {
      if (!confirm('Are you sure you want to clear all logs? This cannot be undone.')) {
        return;
      }

      this.isLoading = true;
      
      try {
        await this.apiRequest('DELETE', '/logs');
        this.logsData = { items: [], totalItems: 0, totalPages: 1 };
        this.logsStats = null;
        await this.loadLogsStats();
      } catch (error) {
        this.showToast(error.message, 'error');
      } finally {
        this.isLoading = false;
      }
    },

    getStatusClass(status) {
      if (status >= 500) return 'server-error';
      if (status >= 400) return 'client-error';
      if (status >= 300) return 'redirect';
      return 'success';
    },

    // Jobs management
    async loadJobs() {
      this.isLoading = true;

      try {
        let path = `/jobs?page=${this.jobsPage}&perPage=${RECORDS_PER_PAGE}`;

        if (this.jobsFilter.status) {
          path += `&status=${this.jobsFilter.status}`;
        }
        if (this.jobsFilter.name) {
          path += `&name=${encodeURIComponent(this.jobsFilter.name)}`;
        }

        this.jobsData = await this.apiRequest('GET', path);
      } catch (error) {
        this.showToast(error.message, 'error');
        this.jobsData = { items: [], totalItems: 0, totalPages: 1 };
      } finally {
        this.isLoading = false;
      }
    },

    async loadJobsStats() {
      try {
        this.jobsStats = await this.apiRequest('GET', '/jobs/stats');
      } catch (error) {
        console.error('Failed to load jobs stats:', error);
      }
    },

    async handleRetryJob(jobId) {
      try {
        await this.apiRequest('POST', `/jobs/${jobId}/retry`);
        this.showToast('Job queued for retry', 'success');
        await this.loadJobs();
        await this.loadJobsStats();
      } catch (error) {
        this.showToast(error.message, 'error');
      }
    },

    async handleRetryAllJobs() {
      if (!confirm('Are you sure you want to retry all failed jobs?')) {
        return;
      }

      this.isLoading = true;

      try {
        const result = await this.apiRequest('POST', '/jobs/retry-all');
        this.showToast(`${result.retried || 0} job(s) queued for retry`, 'success');
        await this.loadJobs();
        await this.loadJobsStats();
      } catch (error) {
        this.showToast(error.message, 'error');
      } finally {
        this.isLoading = false;
      }
    },

    async handleDeleteJob(jobId) {
      if (!confirm('Are you sure you want to delete this job?')) {
        return;
      }

      try {
        await this.apiRequest('DELETE', `/jobs/${jobId}`);
        await this.loadJobs();
        await this.loadJobsStats();
      } catch (error) {
        this.showToast(error.message, 'error');
      }
    },

    async handleClearJobs(status) {
      const statusLabel = status || 'all';
      if (!confirm(`Are you sure you want to clear ${statusLabel} jobs? This cannot be undone.`)) {
        return;
      }

      this.isLoading = true;

      try {
        let path = '/jobs';
        if (status) {
          path += `?status=${status}`;
        }
        await this.apiRequest('DELETE', path);
        await this.loadJobs();
        await this.loadJobsStats();
        this.showToast(`${statusLabel} jobs cleared`, 'success');
      } catch (error) {
        this.showToast(error.message, 'error');
      } finally {
        this.isLoading = false;
      }
    },

    getJobStatusClass(status) {
      const classes = {
        pending: 'pending',
        running: 'running',
        completed: 'success',
        failed: 'failed'
      };
      return classes[status] || 'pending';
    },

    // Crons management
    async loadCrons() {
      this.isLoading = true;

      try {
        this.cronsData = await this.apiRequest('GET', '/crons');
      } catch (error) {
        this.showToast(error.message, 'error');
        this.cronsData = { items: [] };
      } finally {
        this.isLoading = false;
      }
    },

    formatCronNextRun(timestamp) {
      if (!timestamp) return '—';
      const date = new Date(timestamp * 1000);
      return date.toLocaleString();
    },

    handleFileSelect(event, fieldName) {
      const file = event.target.files[0];
      if (file) {
        this.fileUploads[fieldName] = file;

        if (file.type.startsWith('image/')) {
          const reader = new FileReader();
          reader.onload = (e) => {
            this.filePreviews[fieldName] = e.target.result;
          };
          reader.readAsDataURL(file);
        } else {
          delete this.filePreviews[fieldName];
        }
      }
    },

    clearFileUpload(fieldName) {
      delete this.fileUploads[fieldName];
      delete this.filePreviews[fieldName];
      const input = document.getElementById('file-' + fieldName);
      if (input) input.value = '';
    },

    clearExistingFile(fieldName) {
      this.filesToRemove.push(fieldName);
      delete this.recordFormData[fieldName];
    },

    getExistingFile(fieldName) {
      const fileData = this.recordFormData[fieldName];
      if (!fileData) return null;

      if (typeof fileData === 'string') {
        try {
          return JSON.parse(fileData);
        } catch {
          return null;
        }
      }
      return fileData;
    },

    getFileUrl(fieldName) {
      const file = this.getExistingFile(fieldName);
      if (!file || !file.filename) return '';

      const collectionName = this.routeParams.collectionName;
      const recordId = this.routeParams.recordId;
      return `/api/files/${collectionName}/${recordId}/${file.filename}`;
    },

    isImageFile(file) {
      if (!file || !file.mime_type) return false;
      return file.mime_type.startsWith('image/');
    },

    formatFileSize(bytes) {
      if (bytes === 0) return '0 B';
      const k = 1024;
      const sizes = ['B', 'KB', 'MB', 'GB'];
      const i = Math.floor(Math.log(bytes) / Math.log(k));
      return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
    },

    handlePreviousPage() {
      if (this.currentPage > 1) {
        this.currentPage--;
        this.loadRecords();
      }
    },

    handleNextPage() {
      if (this.currentPage < this.totalPages) {
        this.currentPage++;
        this.loadRecords();
      }
    },

    toggleSort(fieldName) {
      if (this.sortField === fieldName) {
        if (this.sortDirection === 'asc') {
          this.sortDirection = 'desc';
        } else if (this.sortDirection === 'desc') {
          this.sortField = '';
          this.sortDirection = '';
        }
      } else {
        this.sortField = fieldName;
        this.sortDirection = 'asc';
      }
      this.currentPage = 1;
      this.loadRecords();
    },

    getSortIndicator(fieldName) {
      if (this.sortField !== fieldName) {
        return '';
      }
      return this.sortDirection === 'asc' ? '▲' : '▼';
    },

    schemaToArray(schema) {
      if (!schema) {
        return [];
      }
      if (Array.isArray(schema)) {
        return schema;
      }
      return Object.entries(schema).map(([fieldName, fieldDef]) => ({
        name: fieldName,
        type: fieldDef.type || 'text',
        required: fieldDef.required || false,
        options: fieldDef
      }));
    },

    get filteredCollections() {
      const collections = this.collections || [];
      if (this.collectionSearchQuery.trim()) {
        const query = this.collectionSearchQuery.toLowerCase().trim();
        return collections.filter(c =>
          c.name.toLowerCase().includes(query) ||
          (c.type || 'base').toLowerCase().includes(query)
        );
      }
      return collections;
    },

    get collectionsTotalPages() {
      return Math.ceil(this.filteredCollections.length / COLLECTIONS_PER_PAGE) || 1;
    },

    get paginatedCollections() {
      const start = (this.collectionsPage - 1) * COLLECTIONS_PER_PAGE;
      return this.filteredCollections.slice(start, start + COLLECTIONS_PER_PAGE);
    },

    get currentCollection() {
      return this.collections.find(c => c.name === this.routeParams.collectionName);
    },

    get visibleFields() {
      return this.schemaToArray(this.currentCollection?.schema).slice(0, MAX_VISIBLE_FIELDS);
    },

    get editableFields() {
      return this.schemaToArray(this.currentCollection?.schema);
    },

    get isAuthCollection() {
      return this.currentCollection?.type === 'auth';
    },

    get passwordsMatch() {
      if (!this.passwordField && !this.passwordConfirmField) {
        return true;
      }
      return this.passwordField === this.passwordConfirmField;
    },

    hasUnsavedChanges() {
      if (Object.keys(this.fileUploads).length > 0) {
        return true;
      }

      if (this.passwordField || this.passwordConfirmField) {
        return true;
      }

      const original = JSON.stringify(this.originalRecordData);
      const current = JSON.stringify(this.recordFormData);
      return original !== current;
    },

    isTextFieldType(fieldType) {
      return ['string', 'text', 'email', 'url'].includes(fieldType);
    },

    isTextareaFieldType(fieldType) {
      return ['json', 'editor'].includes(fieldType);
    },

    getInputType(fieldType) {
      const typeMap = {
        'email': 'email',
        'url': 'url',
        'text': 'text'
      };
      return typeMap[fieldType] || 'text';
    },

    formatFieldValue(value, fieldType) {
      if (value === null || value === undefined) {
        return '—';
      }

      if (fieldType === 'bool' || fieldType === 'boolean') {
        return value ? 'Yes' : 'No';
      }

      if (fieldType === 'json') {
        const jsonString = JSON.stringify(value);
        if (jsonString.length > 50) {
          return jsonString.slice(0, 50) + '...';
        }
        return jsonString;
      }

      if (typeof value === 'string' && value.length > 50) {
        return value.slice(0, 50) + '...';
      }

      return value;
    },

    formatDate(timestamp) {
      if (!timestamp) {
        return '—';
      }

      const date = new Date(timestamp * 1000);
      return date.toLocaleDateString();
    },

    getFieldIcon(type) {
      return FIELD_ICONS[type] || FIELD_ICONS.text;
    },

    showToast(message, type = 'info', duration = 4000) {
      const id = ++this.toastIdCounter;
      const toast = { id, message, type, removing: false };
      this.toasts.push(toast);

      if (duration > 0) {
        setTimeout(() => this.removeToast(id), duration);
      }

      return id;
    },

    removeToast(id) {
      const toast = this.toasts.find(t => t.id === id);
      if (toast) {
        toast.removing = true;
        setTimeout(() => {
          this.toasts = this.toasts.filter(t => t.id !== id);
        }, 200);
      }
    },

    getToastIcon(type) {
      const icons = {
        error: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/></svg>',
        success: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/></svg>',
        warning: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>',
        info: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>'
      };
      return icons[type] || icons.info;
    },

    openCollectionModal(collection = null) {
      this.editingCollection = collection;
      this.collectionModalTab = 'fields';
      this.collectionModalError = '';
      this.showFieldTypePicker = false;

      if (collection) {
        const fields = this.schemaToArray(collection.schema).map(f => ({
          name: f.name,
          type: f.type,
          required: f.required || false,
          options: f.options || {}
        }));

        this.collectionForm = {
          name: collection.name,
          type: collection.type || 'base',
          fields: fields,
          listRule: collection.listRule || '',
          viewRule: collection.viewRule || '',
          createRule: collection.createRule || '',
          updateRule: collection.updateRule || '',
          deleteRule: collection.deleteRule || ''
        };
      } else {
        this.collectionForm = {
          name: '',
          type: 'base',
          fields: [],
          listRule: '',
          viewRule: '',
          createRule: '',
          updateRule: '',
          deleteRule: ''
        };
      }

      this.showCollectionModal = true;
    },

    closeCollectionModal() {
      this.showCollectionModal = false;
      this.editingCollection = null;
      this.collectionModalError = '';
    },

    addField(type) {
      const fieldCount = this.collectionForm.fields.length + 1;
      this.collectionForm.fields.push({
        name: `field_${fieldCount}`,
        type: type,
        required: false,
        options: {}
      });
      this.showFieldTypePicker = false;
    },

    removeField(index) {
      this.collectionForm.fields.splice(index, 1);
    },

    async handleSaveCollection() {
      this.isLoading = true;
      this.collectionModalError = '';

      try {
        if (!this.collectionForm.name.trim()) {
          throw new Error('Collection name is required');
        }

        const schema = {};
        for (const field of this.collectionForm.fields) {
          if (!field.name.trim()) {
            throw new Error('All fields must have a name');
          }
          schema[field.name] = {
            type: field.type,
            required: field.required
          };
          if (field.options && Object.keys(field.options).length > 0) {
            Object.assign(schema[field.name], field.options);
          }
        }

        const body = {
          name: this.collectionForm.name.trim(),
          type: this.collectionForm.type,
          schema: schema
        };

        if (this.collectionForm.listRule !== '') {
          body.listRule = this.collectionForm.listRule;
        }
        if (this.collectionForm.viewRule !== '') {
          body.viewRule = this.collectionForm.viewRule;
        }
        if (this.collectionForm.createRule !== '') {
          body.createRule = this.collectionForm.createRule;
        }
        if (this.collectionForm.updateRule !== '') {
          body.updateRule = this.collectionForm.updateRule;
        }
        if (this.collectionForm.deleteRule !== '') {
          body.deleteRule = this.collectionForm.deleteRule;
        }

        if (this.editingCollection) {
          await this.apiRequest('PATCH', `/collections/${this.editingCollection.name}`, body);
        } else {
          await this.apiRequest('POST', '/collections', body);
        }

        await this.loadCollections();
        this.closeCollectionModal();
      } catch (error) {
        this.collectionModalError = error.message;
      } finally {
        this.isLoading = false;
      }
    },

    async handleDeleteCollection() {
      if (!this.editingCollection) return;

      const confirmMsg = `Are you sure you want to delete the "${this.editingCollection.name}" collection? This will delete ALL records and cannot be undone.`;
      if (!confirm(confirmMsg)) return;

      this.isLoading = true;
      this.collectionModalError = '';

      try {
        await this.apiRequest('DELETE', `/collections/${this.editingCollection.name}`);
        await this.loadCollections();
        this.closeCollectionModal();
      } catch (error) {
        this.collectionModalError = error.message;
      } finally {
        this.isLoading = false;
      }
    },

    showImportModal: false,
    importData: null,
    importChanges: [],
    importDeleteMissing: false,
    importError: '',

    async handleExport() {
      try {
        const data = await this.apiRequest('GET', '/collections/export');
        const json = JSON.stringify(data, null, 2);
        const blob = new Blob([json], { type: 'application/json' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `motebase_collections_${new Date().toISOString().split('T')[0]}.json`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
      } catch (error) {
        this.showToast(error.message, 'error');
      }
    },

    openImportModal() {
      this.showImportModal = true;
      this.importData = null;
      this.importChanges = [];
      this.importDeleteMissing = false;
      this.importError = '';
    },

    closeImportModal() {
      this.showImportModal = false;
      this.importData = null;
      this.importChanges = [];
      this.importError = '';
    },

    handleImportFileSelect(event) {
      const file = event.target.files[0];
      if (!file) return;

      const reader = new FileReader();
      reader.onerror = () => {
        this.importError = 'Failed to read file';
      };
      reader.onload = (e) => {
        try {
          const parsed = JSON.parse(e.target.result);
          if (!Array.isArray(parsed)) {
            this.importError = 'Invalid format: expected an array of collections';
            this.importData = null;
            this.importChanges = [];
            return;
          }
          this.importData = parsed;
          this.importError = '';
          this.computeImportChanges();
        } catch (err) {
          this.importError = 'Invalid JSON: ' + err.message;
          this.importData = null;
          this.importChanges = [];
        }
      };
      reader.readAsText(file);
    },

    computeImportChanges() {
      if (!this.importData || !Array.isArray(this.importData)) {
        this.importChanges = [];
        return;
      }

      const existingById = {};
      const existingByName = {};
      for (const col of this.collections) {
        existingById[col.id] = col;
        existingByName[col.name] = col;
      }

      const importedIds = new Set(this.importData.map(c => c.id));
      const changes = [];

      for (const col of this.importData) {
        const existingWithId = existingById[col.id];
        const existingWithName = existingByName[col.name];

        if (existingWithId) {
          if (existingWithId.name !== col.name) {
            changes.push({
              type: 'rename',
              name: col.name,
              oldName: existingWithId.name,
              id: col.id
            });
          } else {
            const schemaChanged = JSON.stringify(existingWithId.schema) !== JSON.stringify(col.schema);
            const rulesChanged = ['listRule', 'viewRule', 'createRule', 'updateRule', 'deleteRule']
              .some(r => (existingWithId[r] || '') !== (col[r] || ''));

            if (schemaChanged || rulesChanged) {
              changes.push({
                type: 'update',
                name: col.name,
                id: col.id,
                schemaChanged,
                rulesChanged
              });
            }
          }
        } else if (existingWithName) {
          changes.push({
            type: 'conflict',
            name: col.name,
            error: 'Name already used by another collection'
          });
        } else {
          changes.push({
            type: 'create',
            name: col.name,
            id: col.id,
            fieldCount: Object.keys(col.schema || {}).length
          });
        }
      }

      for (const col of this.collections) {
        if (!importedIds.has(col.id)) {
          changes.push({
            type: 'delete',
            name: col.name,
            id: col.id,
            conditional: true
          });
        }
      }

      this.importChanges = changes;
    },

    get importHasConflicts() {
      return this.importChanges.some(c => c.type === 'conflict');
    },

    get importSummary() {
      const creates = this.importChanges.filter(c => c.type === 'create').length;
      const updates = this.importChanges.filter(c => c.type === 'update').length;
      const renames = this.importChanges.filter(c => c.type === 'rename').length;
      const deletes = this.importDeleteMissing ? this.importChanges.filter(c => c.type === 'delete').length : 0;
      return { creates, updates, renames, deletes };
    },

    async handleImport() {
      if (!this.importData || this.importHasConflicts) return;

      this.isLoading = true;
      this.importError = '';

      try {
        await this.apiRequest('POST', '/collections/import', {
          collections: this.importData,
          deleteMissing: this.importDeleteMissing
        });

        await this.loadCollections();
        this.closeImportModal();
      } catch (error) {
        this.importError = error.message;
      } finally {
        this.isLoading = false;
      }
    }
  };
}

function relationPicker(field) {
  return {
    field: field,
    isOpen: false,
    isLoading: false,
    searchQuery: '',
    options: [],
    selectedRecord: null,

    getTargetCollectionName() {
      const parentData = this.$root._x_dataStack[0];
      if (this.field.options?.collectionId) {
        const col = parentData.collections.find(c => c.id === this.field.options.collectionId);
        return col?.name;
      }
      return this.field.options?.collection;
    },

    async init() {
      const parentData = this.$root._x_dataStack[0];
      const value = parentData.recordFormData[this.field.name];
      if (value) {
        await this.loadSelectedRecord(value);
      }
    },

    async loadSelectedRecord(id) {
      const collection = this.getTargetCollectionName();
      if (!collection || !id) return;

      try {
        const parentData = this.$root._x_dataStack[0];
        this.selectedRecord = await parentData.apiRequest('GET', `/collections/${collection}/records/${id}`);
      } catch (e) {
        console.error('Failed to load related record:', e);
        this.selectedRecord = null;
      }
    },

    openDropdown() {
      this.isOpen = true;
      if (this.options.length === 0) {
        this.searchRecords();
      }
    },

    closeDropdown() {
      this.isOpen = false;
    },

    async searchRecords() {
      const collection = this.getTargetCollectionName();
      if (!collection) return;

      this.isLoading = true;

      try {
        const parentData = this.$root._x_dataStack[0];
        let path = `/collections/${collection}/records?perPage=20`;

        if (this.searchQuery) {
          path += `&filter=${encodeURIComponent(this.searchQuery)}`;
        }

        const data = await parentData.apiRequest('GET', path);
        this.options = data.items || [];
      } catch (e) {
        console.error('Failed to search records:', e);
        this.options = [];
      } finally {
        this.isLoading = false;
      }
    },

    selectOption(option) {
      const parentData = this.$root._x_dataStack[0];
      parentData.recordFormData[this.field.name] = option.id;
      this.selectedRecord = option;
      this.isOpen = false;
      this.searchQuery = '';
    },

    clearSelection() {
      const parentData = this.$root._x_dataStack[0];
      parentData.recordFormData[this.field.name] = null;
      this.selectedRecord = null;
      this.searchQuery = '';
    },

    getRecordDisplayName(record) {
      if (!record) return '';
      const displayFields = ['name', 'title', 'label', 'email', 'username'];
      for (const field of displayFields) {
        if (record[field]) return record[field];
      }
      for (const [key, value] of Object.entries(record)) {
        if (!['id', 'created_at', 'updated_at', 'password_hash'].includes(key) && typeof value === 'string') {
          return value;
        }
      }
      return `Record #${record.id}`;
    }
  };
}
