import { Component, ChangeDetectionStrategy } from '@angular/core';
import { MatToolbarModule } from '@angular/material/toolbar';
import { RouterModule } from '@angular/router';

@Component({
  selector: 'app-anonymous-layout',
  imports: [RouterModule, MatToolbarModule],
  template: `
    <mat-toolbar class="anonymous-toolbar">
      <span>My Application</span>
    </mat-toolbar>
    <div class="anonymous-container">
      <router-outlet></router-outlet>
      <div>
        <h1>RECAPTCHA!!!!!!!!!!!!</h1>
      </div>
    </div>
  `,
  styles: [
    `
      @use '@angular/material' as mat;

      :host {
        @include mat.toolbar-overrides(
          (
            container-background-color: var(--mat-sys-primary),
            container-text-color: var(--mat-sys-on-primary),
          )
        );
      }

      .anonymous-container {
        display: flex;
        justify-content: center;
        align-items: center;
        height: 100%;
        margin-top: -64px;
      }

      .anonymous-toolbar {
        display: flex;
        justify-content: center;
        align-items: center;
      }
    `,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class AnonymousLayoutComponent {}
