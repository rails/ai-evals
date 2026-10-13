import { Controller } from "@hotwired/stimulus"

// The big screen's presence watcher: copies the number of players in the game right now into
// every [data-presence-count] element ("Players: N", the "Answers: x / y" denominator), also when
// a Turbo Stream re-renders them. Until presence answers, they keep the server's count.
export default class extends Controller {
  connect() {
    this.observer = new MutationObserver(() => this.apply())
    this.observer.observe(document.body, { childList: true, subtree: true, characterData: true })
    this.apply()
  }

  disconnect() {
    this.observer.disconnect()
  }

  apply() {
    const count = this.element.querySelector("[data-presence-counter]")?.textContent.trim()
    if (!count) return
    document.querySelectorAll("[data-presence-count]").forEach((target) => {
      if (target.textContent !== count) target.textContent = count
    })
  }
}
