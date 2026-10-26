import { screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { ApiError } from "@/lib/api";
import { options, renderApp } from "@/test/utils";
import type { Options } from "@/lib/types";
import { EMPTY_VALUES, KeywordForm, toPayload, validateKeyword, valuesFromKeyword } from "./keyword-form";

const opts = options() as unknown as Options;

describe("validateKeyword", () => {
  it("accepts a valid form", () => {
    expect(validateKeyword({ ...EMPTY_VALUES, query: "react" }, opts)).toEqual({});
  });

  it("requires a query, ignoring whitespace", () => {
    expect(validateKeyword({ ...EMPTY_VALUES, query: "   \n " }, opts).query).toBe("form.errorRequired");
  });

  it("enforces the length limits that the API reports", () => {
    expect(validateKeyword({ ...EMPTY_VALUES, query: "a".repeat(200) }, opts).query).toBeUndefined();
    expect(validateKeyword({ ...EMPTY_VALUES, query: "a".repeat(201) }, opts).query).toBe("form.errorTooLong");
    expect(validateKeyword({ ...EMPTY_VALUES, query: "x", location: "l".repeat(101) }, opts).location).toBe("form.errorTooLong");
  });

  it("only accepts countries and languages the API offers", () => {
    const errors = validateKeyword({ ...EMPTY_VALUES, query: "x", country: "zz", language: "xx" }, opts);
    expect(errors.country).toBe("form.errorChoose");
    expect(errors.language).toBe("form.errorChoose");
  });
});

describe("toPayload", () => {
  it("turns blank optional fields into null so they can be cleared", () => {
    expect(toPayload({ ...EMPTY_VALUES, query: "x", location: "  ", target_domain: "" })).toMatchObject({ location: null, target_domain: null });
  });

  it("trims and passes optional values through", () => {
    expect(toPayload({ ...EMPTY_VALUES, query: "x", location: " Manila ", target_domain: " react.dev " })).toMatchObject({ location: "Manila", target_domain: "react.dev" });
  });

  it("round-trips an existing keyword", () => {
    const values = valuesFromKeyword({ id: 1, query: "q", engine: "google", country: "ph", language: "en", location: null, target_domain: "react.dev", active: false, schedule: "weekly", created_at: "", updated_at: "" });
    expect(values).toEqual({ query: "q", country: "ph", language: "en", location: "", target_domain: "react.dev", schedule: "weekly", active: false });
  });
});

describe("KeywordForm", () => {
  it("shows what is wrong, in a summary that lists the fields, and moves focus to it", async () => {
    const onSubmit = vi.fn();
    renderApp(<KeywordForm options={opts} submitLabel="Create" onSubmit={onSubmit} />);

    await userEvent.click(screen.getByRole("button", { name: "Create" }));

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent("Please fix the following:");
    expect(alert).toHaveTextContent("Search query: This field is required.");
    await waitFor(() => expect(alert).toHaveFocus());
    expect(onSubmit).not.toHaveBeenCalled();
  });

  it("marks the invalid field and ties the message to it", async () => {
    renderApp(<KeywordForm options={opts} submitLabel="Create" onSubmit={vi.fn()} />);
    await userEvent.click(screen.getByRole("button", { name: "Create" }));

    const input = screen.getByRole("textbox", { name: /Search query/ });
    expect(input).toHaveAttribute("aria-invalid", "true");
    expect(input).toHaveAccessibleDescription(/This field is required/);
  });

  it("submits the normalized payload", async () => {
    const onSubmit = vi.fn().mockResolvedValue(undefined);
    renderApp(<KeywordForm options={opts} submitLabel="Create" onSubmit={onSubmit} />);

    await userEvent.type(screen.getByRole("textbox", { name: /Search query/ }), "react developer");
    await userEvent.selectOptions(screen.getByRole("combobox", { name: /Country/ }), "ph");
    await userEvent.type(screen.getByRole("textbox", { name: /Target domain/ }), "react.dev");
    await userEvent.selectOptions(screen.getByRole("combobox", { name: /Schedule/ }), "daily");
    await userEvent.click(screen.getByRole("button", { name: "Create" }));

    expect(onSubmit).toHaveBeenCalledWith({
      query: "react developer", country: "ph", language: "en", location: null, target_domain: "react.dev", schedule: "daily", active: true,
    });
  });

  it("shows the API's field errors next to the fields", async () => {
    const onSubmit = vi.fn().mockRejectedValue(
      new ApiError(422, "validation_failed", "Validation failed", { query: ["already exists with the same search settings"], target_domain: ["is not a valid domain"] }),
    );
    renderApp(<KeywordForm options={opts} submitLabel="Create" onSubmit={onSubmit} />);
    await userEvent.type(screen.getByRole("textbox", { name: /Search query/ }), "react");
    await userEvent.click(screen.getByRole("button", { name: "Create" }));

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent("Search query: already exists with the same search settings");
    expect(alert).toHaveTextContent("Target domain (optional): is not a valid domain");
    expect(screen.getByRole("textbox", { name: /Search query/ })).toHaveAttribute("aria-invalid", "true");
  });

  it("shows record-level errors such as the keyword limit", async () => {
    const onSubmit = vi.fn().mockRejectedValue(new ApiError(422, "validation_failed", "x", { base: ["keyword limit reached (50)"] }));
    renderApp(<KeywordForm options={opts} submitLabel="Create" onSubmit={onSubmit} />);
    await userEvent.type(screen.getByRole("textbox", { name: /Search query/ }), "react");
    await userEvent.click(screen.getByRole("button", { name: "Create" }));

    expect(await screen.findByText("keyword limit reached (50)")).toBeInTheDocument();
  });

  it("shows other failures without losing what was typed", async () => {
    const onSubmit = vi.fn().mockRejectedValue(new ApiError(0, "network_error", "The server could not be reached"));
    renderApp(<KeywordForm options={opts} submitLabel="Create" onSubmit={onSubmit} />);
    await userEvent.type(screen.getByRole("textbox", { name: /Search query/ }), "react");
    await userEvent.click(screen.getByRole("button", { name: "Create" }));

    expect(await screen.findByText("The server could not be reached")).toBeInTheDocument();
    expect(screen.getByRole("textbox", { name: /Search query/ })).toHaveValue("react");
  });

  it("clears a field's server error once that field is edited", async () => {
    const onSubmit = vi.fn().mockRejectedValue(new ApiError(422, "validation_failed", "x", { query: ["already exists"] }));
    renderApp(<KeywordForm options={opts} submitLabel="Create" onSubmit={onSubmit} />);
    const input = screen.getByRole("textbox", { name: /Search query/ });
    await userEvent.type(input, "react");
    await userEvent.click(screen.getByRole("button", { name: "Create" }));
    await screen.findByRole("alert");

    await userEvent.type(input, "!");

    expect(input).not.toHaveAttribute("aria-invalid", "true");
  });

  it("disables the button while saving", async () => {
    let finish!: () => void;
    const onSubmit = vi.fn(() => new Promise<void>((resolve) => { finish = resolve; }));
    renderApp(<KeywordForm options={opts} submitLabel="Create" onSubmit={onSubmit} />);
    await userEvent.type(screen.getByRole("textbox", { name: /Search query/ }), "react");
    await userEvent.click(screen.getByRole("button", { name: "Create" }));

    expect(await screen.findByRole("button", { name: "Saving…" })).toBeDisabled();
    finish();
    await waitFor(() => expect(screen.getByRole("button", { name: "Create" })).toBeEnabled());
  });

  it("offers only the schedules and countries the API offers, with localized names", () => {
    renderApp(<KeywordForm options={opts} submitLabel="Create" onSubmit={vi.fn()} />, { locale: "ko" });
    const country = screen.getByRole("combobox", { name: /국가/ });
    expect(country.querySelectorAll("option")).toHaveLength(4);
    expect(screen.getByRole("option", { name: "필리핀 (ph)" })).toBeInTheDocument();
    expect(screen.getByRole("option", { name: "매일" })).toBeInTheDocument();
  });

  it("fills in the initial values when editing", () => {
    renderApp(<KeywordForm options={opts} submitLabel="Save" initial={{ ...EMPTY_VALUES, query: "vue", country: "kr", active: false }} onSubmit={vi.fn()} onCancel={vi.fn()} />);
    expect(screen.getByRole("textbox", { name: /Search query/ })).toHaveValue("vue");
    expect(screen.getByRole("combobox", { name: /Country/ })).toHaveValue("kr");
    expect(screen.getByRole("checkbox", { name: "Active" })).not.toBeChecked();
    expect(screen.getByRole("button", { name: "Cancel" })).toBeInTheDocument();
  });
});
