import { ComponentFixture, TestBed } from '@angular/core/testing';
import { DashboardComponent } from './dashboard.component';
import { describe, it, expect, beforeEach } from 'vitest'; // Added Vitest globals
import { provideZonelessChangeDetection } from '@angular/core';

// If DashboardComponent uses any Material modules directly in its template,
// and it's a standalone component, those modules should be in its OWN imports array.
// For testing, we often import NoopAnimationsModule.
// If DashboardComponent itself imports MatCardModule etc., that's handled by importing DashboardComponent.

describe('DashboardComponent', () => {
  let component: DashboardComponent;
  let fixture: ComponentFixture<DashboardComponent>;

  beforeEach(async () => {
    // Make it async for compileComponents
    await TestBed.configureTestingModule({
      imports: [
        DashboardComponent, // Import standalone component
      ],
      providers: [provideZonelessChangeDetection()],
    }).compileComponents(); // Important if DashboardComponent uses templateUrl/styleUrls

    fixture = TestBed.createComponent(DashboardComponent);
    component = fixture.componentInstance;
    fixture.detectChanges();
  });

  it('should create', () => {
    // Renamed from 'should compile'
    expect(component).toBeTruthy();
  });
});
