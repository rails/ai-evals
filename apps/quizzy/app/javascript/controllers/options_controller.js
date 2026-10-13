import { Controller } from "@hotwired/stimulus"

// Adds and removes answer option rows in the question form,
// keeping the rows' labels numbered in order ("Option 1", "Option 2", ...)
export default class extends Controller {
  static targets = ["list", "template", "row"]

  add() {
    const html = this.templateTarget.innerHTML.replaceAll("NEW_INDEX", Date.now().toString())
    this.listTarget.insertAdjacentHTML("beforeend", html)
    this.renumber()
    this.rowTargets.at(-1).querySelector("input[type=text]").focus()
  }

  remove(event) {
    event.target.closest("[data-options-target=row]").remove()
    this.renumber()
  }

  renumber() {
    this.rowTargets.forEach((row, index) => {
      row.querySelectorAll("[data-label]").forEach((element) => {
        const label = element.dataset.label.replace("%", index + 1)
        element.setAttribute("aria-label", label)
        if (element.placeholder !== undefined && element.type === "text") element.placeholder = label
      })
    })
  }
}
