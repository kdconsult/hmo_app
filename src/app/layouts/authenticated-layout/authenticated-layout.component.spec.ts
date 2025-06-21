import { waitForAsync, ComponentFixture, TestBed } from '@angular/core/testing';

import { AuthenticatedLayoutComponent } from './authenticated-layout.component';

describe('AuthenticatedLayoutComponent', () => {
  let component: AuthenticatedLayoutComponent;
  let fixture: ComponentFixture<AuthenticatedLayoutComponent>;

  beforeEach(waitForAsync(() => {
    TestBed.configureTestingModule({
      declarations: [AuthenticatedLayoutComponent],
      imports: [
        MatButtonModule,
        MatIconModule,
        MatListModule,
        MatSidenavModule,
        MatToolbarModule,
      ]
    });
  }));

  beforeEach(() => {
    fixture = TestBed.createComponent(AuthenticatedLayoutComponent);
    component = fixture.componentInstance;
    fixture.detectChanges();
  });

  it('should compile', () => {
    expect(component).toBeTruthy();
  });
});
