<script lang="ts">
  import { onMount } from 'svelte';
  import { benchmarkAPI, type BenchmarkJob } from '$lib/api';

  let jobs: BenchmarkJob[] = [];
  let loading = true;
  let error = '';

  onMount(async () => {
    await loadJobs();
    // Auto-refresh every 5 seconds
    const interval = setInterval(loadJobs, 5000);
    return () => clearInterval(interval);
  });

  async function loadJobs() {
    try {
      const response = await benchmarkAPI.listJobs();
      jobs = response.data;
      error = '';
    } catch (err) {
      console.error('Failed to load jobs:', err);
      error = 'Failed to connect to API. Make sure the backend is running on http://localhost:8000';
    } finally {
      loading = false;
    }
  }

  async function startBenchmark() {
    try {
      await benchmarkAPI.start({
        test_type: 'http',
        mesh_type: 'baseline',
        namespace: 'default',
        duration: 60,
        concurrent_connections: 100
      });
      await loadJobs();
    } catch (err) {
      console.error('Failed to start benchmark:', err);
      error = 'Failed to start benchmark';
    }
  }
</script>

<div class="container mx-auto p-8">
  <h1 class="text-4xl font-bold mb-8">Service Mesh Benchmark Dashboard</h1>

  <div class="mb-6">
    <button
      on:click={startBenchmark}
      class="bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded"
    >
      Start Benchmark
    </button>
  </div>

  {#if error}
    <div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
      {error}
    </div>
  {/if}

  {#if loading}
    <p class="text-gray-600">Loading...</p>
  {:else if jobs.length === 0}
    <div class="bg-yellow-100 border border-yellow-400 text-yellow-700 px-4 py-3 rounded">
      No benchmark jobs found. Click "Start Benchmark" to create one.
    </div>
  {:else}
    <div class="bg-white shadow-md rounded-lg overflow-hidden">
      <table class="min-w-full">
        <thead class="bg-gray-50">
          <tr>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Job ID</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Type</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Mesh</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
            <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Started</th>
          </tr>
        </thead>
        <tbody class="bg-white divide-y divide-gray-200">
          {#each jobs as job}
            <tr>
              <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">{job.job_id}</td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{job.test_type}</td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{job.mesh_type}</td>
              <td class="px-6 py-4 whitespace-nowrap">
                <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full
                  {job.status === 'pending' ? 'bg-yellow-100 text-yellow-800' : ''}
                  {job.status === 'running' ? 'bg-blue-100 text-blue-800' : ''}
                  {job.status === 'completed' ? 'bg-green-100 text-green-800' : ''}
                  {job.status === 'failed' ? 'bg-red-100 text-red-800' : ''}
                ">
                  {job.status}
                </span>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                {new Date(job.started_at).toLocaleString()}
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {/if}
</div>
