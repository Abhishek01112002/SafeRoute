import asyncio
import httpx
import time
import statistics

BASE_URL = "http://localhost:8000"
CONCURRENT_USERS = 50
REQUESTS_PER_USER = 5

async def simulate_user(user_id: int):
    async with httpx.AsyncClient(timeout=10.0) as client:
        latencies = []
        success_count = 0
        
        for i in range(REQUESTS_PER_USER):
            start_time = time.perf_counter()
            try:
                # Test health endpoint (read-heavy simulation)
                response = await client.get(f"{BASE_URL}/health")
                latency = time.perf_counter() - start_time
                if response.status_code == 200:
                    success_count += 1
                    latencies.append(latency)
            except Exception as e:
                print(f"User {user_id} error: {e}")
            
            await asyncio.sleep(0.1)  # Thinking time
            
        return success_count, latencies

async def run_load_test():
    print(f"🚀 Starting Load Test: {CONCURRENT_USERS} users, {REQUESTS_PER_USER} requests/user")
    start_time = time.perf_counter()
    
    tasks = [simulate_user(i) for i in range(CONCURRENT_USERS)]
    results = await asyncio.gather(*tasks)
    
    total_time = time.perf_counter() - start_time
    total_success = sum(r[0] for r in results)
    all_latencies = [l for r in results for l in r[1]]
    
    total_reqs = CONCURRENT_USERS * REQUESTS_PER_USER
    
    print("\n" + "="*40)
    print("📊 LOAD TEST RESULTS")
    print("="*40)
    print(f"Total Requests: {total_reqs}")
    print(f"Success Rate:   {(total_success/total_reqs)*100:.1f}%")
    print(f"Total Duration: {total_time:.2f}s")
    print(f"Throughput:     {total_success/total_time:.2f} req/s")
    
    if all_latencies:
        print(f"Avg Latency:    {statistics.mean(all_latencies)*1000:.1f}ms")
        print(f"P95 Latency:    {statistics.quantiles(all_latencies, n=20)[18]*1000:.1f}ms")
    print("="*40)

if __name__ == "__main__":
    try:
        asyncio.run(run_load_test())
    except KeyboardInterrupt:
        pass
