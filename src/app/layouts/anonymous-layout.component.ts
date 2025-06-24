import { Component, ChangeDetectionStrategy } from '@angular/core';
import { RouterModule } from '@angular/router';

@Component({
  selector: 'app-anonymous-layout',
  imports: [RouterModule],
  template: `
    <div class="anonymous-container">
      <router-outlet></router-outlet>
    </div>
  `,
  styles: [
    `
      :host {
        display: block;
        height: 100%;
      }

      .anonymous-container {
        display: flex;
        justify-content: center;
        align-items: center;
        height: 100%;
      }
    `,
  ],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class AnonymousLayoutComponent {}
