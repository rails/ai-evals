import { Controller } from "@hotwired/stimulus"

// Counts down to the question's deadline on the moderator's screen (M:SS) and
// finishes the question when the time is up, as if the moderator clicked "Finish".
// The deadline comes from the server, so reloading the page doesn't restart the timer;
// the server's "now" at render time compensates for a skewed local clock.
export default class extends Controller {
  static targets = ["display", "finish"]
  static values = { deadline: String, now: String }

  connect() {
    this.start()
  }

  disconnect() {
    this.stop()
  }

  deadlineValueChanged() {
    if (this.timer) this.start()
  }

  start() {
    this.stop()
    this.submitted = false
    const skew = Date.now() - Date.parse(this.nowValue)
    this.deadline = Date.parse(this.deadlineValue) + skew
    this.tick()
    this.timer = setInterval(() => this.tick(), 250)
  }

  stop() {
    clearInterval(this.timer)
    this.timer = null
  }

  tick() {
    const left = Math.max(0, Math.ceil((this.deadline - Date.now()) / 1000))
    if (this.hasDisplayTarget) {
      this.displayTarget.textContent = `${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")}`
    }
    if (left === 0) this.finish()
  }

  finish() {
    this.stop()
    if (this.submitted || !this.hasFinishTarget) return

    this.submitted = true
    this.finishTarget.requestSubmit()
  }
}
