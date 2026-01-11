describe("jobs", function()
    local db = require("motebase.db")
    local jobs = require("motebase.jobs")
    local migrations = require("motebase.migrations")

    before_each(function()
        db.open(":memory:")
        migrations.run()
        jobs.clear_all()
        jobs.clear_handlers()
    end)

    after_each(function()
        db.close()
    end)

    describe("queue", function()
        it("queues a job with default options", function()
            local job_id = jobs.queue("send_email", { to = "test@example.com" })
            assert.is_number(job_id)

            local job = jobs.get(job_id)
            assert.is_not_nil(job)
            assert.are.equal("send_email", job.name)
            assert.are.equal("pending", job.status)
            assert.are.equal("normal", job.priority)
            assert.are.equal(1, job.max_attempts)
            assert.is_table(job.payload)
            assert.are.equal("test@example.com", job.payload.to)
        end)

        it("queues a job with custom options", function()
            local job_id = jobs.queue("important_task", { data = 123 }, {
                priority = "high",
                attempts = 5,
            })

            local job = jobs.get(job_id)
            assert.are.equal("high", job.priority)
            assert.are.equal(5, job.max_attempts)
        end)

        it("queues a delayed job", function()
            local job_id = jobs.queue("delayed_task", nil, { delay = 3600 })

            local job = jobs.get(job_id)
            assert.is_number(job.run_at)
            assert.is_true(job.run_at > os.time())
        end)

        it("rejects invalid job name", function()
            local job_id, err = jobs.queue("", {})
            assert.is_nil(job_id)
            assert.is_string(err)
        end)

        it("rejects invalid priority", function()
            local job_id, err = jobs.queue("test", {}, { priority = "urgent" })
            assert.is_nil(job_id)
            assert.is_string(err)
        end)
    end)

    describe("handler registration", function()
        it("registers a handler", function()
            local ok = jobs.register("test_job", function() end)
            assert.is_true(ok)
            assert.is_function(jobs.get_handler("test_job"))
        end)

        it("lists registered handlers", function()
            jobs.register("job_a", function() end)
            jobs.register("job_b", function() end)

            local handlers = jobs.list_handlers()
            assert.are.equal(2, #handlers)
            assert.are.same({ "job_a", "job_b" }, handlers)
        end)

        it("unregisters a handler", function()
            jobs.register("temp_job", function() end)
            assert.is_function(jobs.get_handler("temp_job"))

            jobs.unregister("temp_job")
            assert.is_nil(jobs.get_handler("temp_job"))
        end)
    end)

    describe("claim_next", function()
        it("claims the next pending job", function()
            jobs.queue("first", {})
            jobs.queue("second", {})

            local claimed = jobs.claim_next()
            assert.is_not_nil(claimed)
            assert.are.equal("first", claimed.name)
            assert.are.equal("running", claimed.status)
            assert.are.equal(1, claimed.attempts)
        end)

        it("respects priority order", function()
            jobs.queue("low_priority", {}, { priority = "low" })
            jobs.queue("high_priority", {}, { priority = "high" })
            jobs.queue("normal_priority", {}, { priority = "normal" })

            local first = jobs.claim_next()
            assert.are.equal("high_priority", first.name)

            jobs.mark_completed(first.id)

            local second = jobs.claim_next()
            assert.are.equal("normal_priority", second.name)
        end)

        it("skips jobs scheduled for later", function()
            jobs.queue("later", {}, { delay = 3600 })
            jobs.queue("now", {})

            local claimed = jobs.claim_next()
            assert.are.equal("now", claimed.name)
        end)

        it("returns nil when no jobs available", function()
            local claimed = jobs.claim_next()
            assert.is_nil(claimed)
        end)
    end)

    describe("process", function()
        it("completes a successful job", function()
            jobs.register("success_job", function(payload)
                return { result = "done", input = payload.value }
            end)

            local job_id = jobs.queue("success_job", { value = 42 })
            local job = jobs.claim_next()
            jobs.process(job)

            local completed = jobs.get(job_id)
            assert.are.equal("completed", completed.status)
            assert.is_table(completed.result)
            assert.are.equal("done", completed.result.result)
        end)

        it("fails a job with no handler", function()
            local job_id = jobs.queue("unknown_job", {})
            local job = jobs.claim_next()
            jobs.process(job)

            local failed = jobs.get(job_id)
            assert.are.equal("failed", failed.status)
            assert.is_string(failed.error)
        end)

        it("retries a failed job if attempts remain", function()
            jobs.register("flaky_job", function()
                error("temporary failure")
            end)

            local job_id = jobs.queue("flaky_job", {}, { attempts = 3 })
            local job = jobs.claim_next()
            jobs.process(job)

            local retried = jobs.get(job_id)
            assert.are.equal("pending", retried.status)
            assert.are.equal(1, retried.attempts)
            assert.is_number(retried.run_at)
        end)

        it("fails a job after max attempts", function()
            jobs.register("always_fails", function()
                error("permanent failure")
            end)

            local job_id = jobs.queue("always_fails", {}, { attempts = 2 })

            local job1 = jobs.claim_next()
            jobs.process(job1)
            assert.are.equal("pending", jobs.get(job_id).status)

            -- Clear the run_at delay so we can claim it again immediately
            db.run("UPDATE _jobs SET run_at = NULL WHERE id = ?", { job_id })

            local job2 = jobs.claim_next()
            assert.is_not_nil(job2)
            jobs.process(job2)

            local failed = jobs.get(job_id)
            assert.are.equal("failed", failed.status)
            assert.are.equal(2, failed.attempts)
        end)
    end)

    describe("job management", function()
        it("lists jobs with pagination", function()
            for i = 1, 5 do
                jobs.queue("job_" .. i, {})
            end

            local result = jobs.list({ page = 1, per_page = 2 })
            assert.are.equal(5, result.totalItems)
            assert.are.equal(3, result.totalPages)
            assert.are.equal(2, #result.items)
        end)

        it("filters jobs by status", function()
            jobs.queue("pending_job", {})
            local job_id = jobs.queue("completed_job", {})
            jobs.mark_completed(job_id)

            local pending = jobs.list({ status = "pending" })
            assert.are.equal(1, pending.totalItems)
            assert.are.equal("pending_job", pending.items[1].name)
        end)

        it("gets job statistics", function()
            jobs.queue("p1", {})
            jobs.queue("p2", {})
            local cid = jobs.queue("c1", {})
            jobs.mark_completed(cid)
            local fid = jobs.queue("f1", {})
            jobs.mark_failed(fid, "error")

            local stats = jobs.stats()
            assert.are.equal(2, stats.pending)
            assert.are.equal(0, stats.running)
            assert.are.equal(1, stats.completed)
            assert.are.equal(1, stats.failed)
            assert.are.equal(4, stats.total)
        end)

        it("retries a failed job", function()
            local job_id = jobs.queue("retry_me", {})
            jobs.mark_failed(job_id, "failed")

            local ok = jobs.retry(job_id)
            assert.is_true(ok)

            local retried = jobs.get(job_id)
            assert.are.equal("pending", retried.status)
            assert.are.equal(0, retried.attempts)
            assert.is_nil(retried.error)
        end)

        it("retries all failed jobs", function()
            local id1 = jobs.queue("fail1", {})
            local id2 = jobs.queue("fail2", {})
            jobs.mark_failed(id1, "e1")
            jobs.mark_failed(id2, "e2")

            local count = jobs.retry_all_failed()
            assert.are.equal(2, count)
            assert.are.equal("pending", jobs.get(id1).status)
            assert.are.equal("pending", jobs.get(id2).status)
        end)

        it("deletes a job", function()
            local job_id = jobs.queue("delete_me", {})
            assert.is_true(jobs.delete(job_id))
            assert.is_nil(jobs.get(job_id))
        end)

        it("clears completed jobs", function()
            local cid = jobs.queue("c", {})
            jobs.mark_completed(cid)
            jobs.queue("p", {})

            local count = jobs.clear("completed")
            assert.are.equal(1, count)
            assert.is_nil(jobs.get(cid))
        end)
    end)

    describe("timeout", function()
        it("queues a job with custom timeout", function()
            local job_id = jobs.queue("slow_task", {}, { timeout = 60 })
            local job = jobs.get(job_id)
            assert.are.equal(60, job.timeout)
        end)

        it("uses default timeout of 30 minutes", function()
            local job_id = jobs.queue("normal_task", {})
            local job = jobs.get(job_id)
            assert.are.equal(1800, job.timeout)
        end)

        it("times out stale running jobs", function()
            local job_id = jobs.queue("stuck_job", {}, { timeout = 10 })

            jobs.claim_next()
            assert.are.equal("running", jobs.get(job_id).status)

            -- Manually set started_at to the past (simulate job running for too long)
            db.run("UPDATE _jobs SET started_at = ? WHERE id = ?", { os.time() - 20, job_id })

            -- Run timeout check
            local count = jobs.timeout_stale()
            assert.are.equal(1, count)

            -- Job should now be failed
            local timed_out = jobs.get(job_id)
            assert.are.equal("failed", timed_out.status)
            assert.are.equal("job timed out", timed_out.error)
        end)

        it("does not timeout jobs within their timeout window", function()
            local job_id = jobs.queue("active_job", {}, { timeout = 3600 })

            -- Claim the job
            jobs.claim_next()
            assert.are.equal("running", jobs.get(job_id).status)

            -- Run timeout check (job just started, shouldn't timeout)
            local count = jobs.timeout_stale()
            assert.are.equal(0, count)

            -- Job should still be running
            assert.are.equal("running", jobs.get(job_id).status)
        end)

        it("times out multiple stale jobs at once", function()
            local id1 = jobs.queue("stuck1", {}, { timeout = 5 })
            local id2 = jobs.queue("stuck2", {}, { timeout = 5 })
            local id3 = jobs.queue("active", {}, { timeout = 3600 })

            -- Claim all jobs
            jobs.claim_next()
            jobs.claim_next()
            jobs.claim_next()

            -- Set first two to be stale
            local past = os.time() - 60
            db.run("UPDATE _jobs SET started_at = ? WHERE id IN (?, ?)", { past, id1, id2 })

            -- Run timeout check
            local count = jobs.timeout_stale()
            assert.are.equal(2, count)

            assert.are.equal("failed", jobs.get(id1).status)
            assert.are.equal("failed", jobs.get(id2).status)
            assert.are.equal("running", jobs.get(id3).status)
        end)
    end)
end)
