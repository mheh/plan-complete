import * as vscode from "vscode";

export interface ContextSettings {
  signature: boolean;
  timeoutMs: number;
}

export interface PlanStatus {
  active: boolean;
  reason: string;
  problem?: string;
  context?: ContextSettings;
}

export class StatusItem {
  private readonly item = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
  current: PlanStatus = { active: false, reason: "starting" };

  constructor(command: string) {
    this.item.command = command;
    this.show(this.current);
  }

  show(status: PlanStatus) {
    this.current = status;
    if (status.active && status.problem) {
      this.item.text = "$(warning) Plan: no model";
      this.item.tooltip = `Plan Complete follows ${status.reason}, but ${status.problem}. Click for options.`;
    } else if (status.active) {
      this.item.text = "$(sparkle) Plan: on";
      this.item.tooltip = `Plan Complete follows ${status.reason}. Click for options.`;
    } else {
      this.item.text = "$(circle-slash) Plan: off";
      this.item.tooltip = `Plan Complete is off: ${status.problem ?? status.reason}. Click for options.`;
    }
    this.item.show();
  }

  dispose() {
    this.item.dispose();
  }
}
