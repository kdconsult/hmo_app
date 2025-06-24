import { Component, ChangeDetectionStrategy } from '@angular/core';
import { MatDialogModule, MatDialogRef } from '@angular/material/dialog';
import { MatButtonModule } from '@angular/material/button';

@Component({
  selector: 'app-terms-and-conditions',
  imports: [MatDialogModule, MatButtonModule],
  templateUrl: './terms-and-conditions.component.html',
  styleUrls: ['./terms-and-conditions.component.scss'],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class TermsAndConditionsComponent {
  constructor(public dialogRef: MatDialogRef<TermsAndConditionsComponent>) {}

  closeDialog(): void {
    this.dialogRef.close();
  }
}
