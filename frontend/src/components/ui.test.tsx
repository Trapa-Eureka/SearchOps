import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { ApiError } from "@/lib/api";
import { renderApp } from "@/test/utils";
import { ConfirmDialog, EmptyState, ErrorState, Field, Loading, Metric, Pagination } from "./ui";

describe("Pagination", () => {
  const meta = (page: number, total_pages: number, total_count = 30) => ({ page, per_page: 10, total_count, total_pages });

  it("renders nothing for a single page", () => {
    renderApp(<Pagination meta={meta(1, 1, 3)} onPage={vi.fn()} />);
    expect(screen.queryByRole("navigation")).not.toBeInTheDocument();
  });

  it("moves between pages and disables the ends", async () => {
    const onPage = vi.fn();
    const { rerender } = renderApp(<Pagination meta={meta(1, 3)} onPage={onPage} />);
    expect(screen.getByRole("button", { name: "Previous" })).toBeDisabled();
    await userEvent.click(screen.getByRole("button", { name: "Next" }));
    expect(onPage).toHaveBeenLastCalledWith(2);

    rerender(<Pagination meta={meta(3, 3)} onPage={onPage} />);
    expect(screen.getByRole("button", { name: "Next" })).toBeDisabled();
    await userEvent.click(screen.getByRole("button", { name: "Previous" }));
    expect(onPage).toHaveBeenLastCalledWith(2);
  });

  it("announces the position", () => {
    renderApp(<Pagination meta={meta(2, 3)} onPage={vi.fn()} />);
    expect(screen.getByRole("navigation", { name: "Pagination" })).toHaveTextContent("Page 2 of 3 (30 items)");
  });
});

describe("ErrorState", () => {
  it("is an alert with a translated title", () => {
    renderApp(<ErrorState error={new ApiError(0, "network_error", "x")} />);
    expect(screen.getByRole("alert")).toHaveTextContent(/could not be reached/);
  });

  it("offers a retry that calls back", async () => {
    const onRetry = vi.fn();
    renderApp(<ErrorState error={new ApiError(500, "http_error", "boom")} onRetry={onRetry} />);
    await userEvent.click(screen.getByRole("button", { name: "Try again" }));
    expect(onRetry).toHaveBeenCalledTimes(1);
  });

  it("shows the numbers of a budget error", () => {
    renderApp(<ErrorState error={new ApiError(429, "search_budget_exceeded", "x", { limit: 5, used: 5 })} />);
    expect(screen.getByRole("alert")).toHaveTextContent("5 of 5 searches used today.");
  });

  it("does not leak the text of an unexpected exception", () => {
    renderApp(<ErrorState error={new Error("internal secret")} />);
    expect(screen.getByRole("alert")).not.toHaveTextContent("internal secret");
  });
});

describe("small pieces", () => {
  it("Loading is a status", () => {
    renderApp(<Loading />);
    // The toast region is a status too, so find the one that carries the text.
    expect(screen.getAllByRole("status").some((node) => node.textContent?.includes("Loading…"))).toBe(true);
  });

  it("EmptyState shows its title, text, and action", () => {
    renderApp(<EmptyState title="Nothing" action={<button>Add</button>}>Add something.</EmptyState>);
    expect(screen.getByText("Nothing")).toBeInTheDocument();
    expect(screen.getByText("Add something.")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Add" })).toBeInTheDocument();
  });

  it("Metric pairs a term with its value", () => {
    renderApp(<dl><Metric label="Success rate" value="80%" hint="8 ok" /></dl>);
    expect(screen.getByRole("term")).toHaveTextContent("Success rate");
    const [value, hint] = screen.getAllByRole("definition");
    expect(value).toHaveTextContent("80%");
    expect(hint).toHaveTextContent("8 ok");
  });

  it("Field links label, hint, and error to the control", () => {
    renderApp(<Field label="Name" hint="Hint text" error="Bad" required>{(props) => <input {...props} />}</Field>);
    const input = screen.getByRole("textbox", { name: /Name/ });
    expect(input).toHaveAttribute("aria-invalid", "true");
    expect(input).toHaveAccessibleDescription("Bad Hint text");
  });
});

describe("ConfirmDialog", () => {
  const setup = (overrides = {}) => {
    const props = { open: true, title: "Delete it?", message: "Cannot be undone.", confirmLabel: "Delete", onConfirm: vi.fn(), onCancel: vi.fn(), ...overrides };
    renderApp(<ConfirmDialog {...props} />);
    return props;
  };

  it("opens as a modal dialog when asked", () => {
    setup();
    expect(document.querySelector("dialog")).toHaveAttribute("open");
  });

  it("is named by its title", () => {
    setup();
    expect(screen.getByRole("dialog", { name: "Delete it?" })).toBeInTheDocument();
  });

  it("confirms and cancels", async () => {
    const props = setup();
    await userEvent.click(screen.getByRole("button", { name: "Delete" }));
    expect(props.onConfirm).toHaveBeenCalledTimes(1);
    await userEvent.click(screen.getByRole("button", { name: "Cancel" }));
    expect(props.onCancel).toHaveBeenCalledTimes(1);
  });

  it("disables both buttons while busy", () => {
    setup({ busy: true });
    expect(screen.getByRole("button", { name: "Delete" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "Cancel" })).toBeDisabled();
  });

  it("stays closed when open is false", () => {
    setup({ open: false });
    expect(document.querySelector("dialog")).not.toHaveAttribute("open");
  });
});
