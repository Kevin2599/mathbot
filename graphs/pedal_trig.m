function main()
   
   figure(1);  clf; hold on; axis equal; axis off
   thickness=4; ball_rad=0.007; i=sqrt(-1);
   red=[1, 0, 0]; blue=[0, 0, 1]; black=[0 0 0]; green=[0, 0.9, 0]; fontsize=30; dist=0.01;
   
   A=-0.5; B=1; C=i; P=0.2+0.4*i; 
   N=return_perp(A, B, P); M=return_perp(C, A, P); L=return_perp(B, C, P);

   % plot sides
   plot(real([A, B]), imag([A, B]), 'color', red, 'linewidth', thickness);
   plot(real([B, C]), imag([B, C]), 'color', red, 'linewidth', thickness);
   plot(real([A, C]), imag([A, C]), 'color', red, 'linewidth', thickness);


%plot heights
   plot(real([L, P]), imag([L, P]), 'color', green, 'linewidth', thickness);
   plot(real([M, P]), imag([M, P]), 'color', green, 'linewidth', thickness);
   plot(real([N, P]), imag([N, P]), 'color', green, 'linewidth', thickness);

% plot pedal
   plot(real([L, M]), imag([L, M]), 'color', blue, 'linewidth', thickness);
   plot(real([L, N]), imag([L, N]), 'color', blue, 'linewidth', thickness);
   plot(real([M, N]), imag([M, N]), 'color', blue, 'linewidth', thickness);

   
   ball(A, ball_rad, red); ball(B, ball_rad, red); ball(C, ball_rad, red);
   ball(L, ball_rad, blue); ball(M, ball_rad, blue); ball(N, ball_rad, blue);
   ball(P, ball_rad, green);

   ang_size=0.07; ang_thick=2;
   plot_angle(P, M, A,   ang_size, ang_thick, red)
   plot_angle(P, N, B,   ang_size, ang_thick, red)
   plot_angle(P, L, C,   ang_size, ang_thick, red)

   place_text_smartly (P, fontsize, 5, 0.004, 'P')
   place_text_smartly (A, fontsize, 5, 0.004, 'A')
   place_text_smartly (B, fontsize, 7, 0.004, 'B')
   place_text_smartly (C, fontsize, 2, 0.004, 'C')
   place_text_smartly (L, fontsize, 1, 0.004, 'L')
   place_text_smartly (M, fontsize, 4, 0.004, 'M')
   place_text_smartly (N, fontsize, 6, 0.004, 'N')
   
   saveas(gcf, 'Pedal_trig_illustration.eps', 'psc2')
   
function d=return_perp(a, b, c)
   
   t=fminbnd(inline('abs (sqrt(-1)*(b-a)/abs(b-a) - (c-t*b-(1-t)*a)/abs(c-t*b-(1-t)*a)) ', 't', 'a', 'b', 'c'), -1, 1, [], a, b, c);
   d=t*b+(1-t)*a;
   
function place_text_smartly (z, fs, pos, d, tx)
   p=cos(pi/4)+sqrt(-1)*sin(pi/4);
   z = z + p^pos * d * fs; 
   shiftx=0.0003;
   shifty=0.002;
   x = real (z); y=imag(z); 
   H=text(x+shiftx*fs, y+shifty*fs, tx); set(H, 'fontsize', fs, 'HorizontalAlignment', 'c', 'VerticalAlignment', 'c')
   
   
function ball(z, r, color)
   x=real(z); y=imag(z);
   Theta=0:0.1:2*pi;
   X=r*cos(Theta)+x;
   Y=r*sin(Theta)+y;
   H=fill(X, Y, color);
   set(H, 'EdgeColor', color);

function plot_angle(a, b, c, dist, thickness, color)

   u=b+dist*(a-b)/abs(a-b);
   v=b+dist*(c-b)/abs(c-b);
   w=u+v-b;

   plot(real([u, w, v]), imag([u, w, v]), 'color', color, 'linewidth', thickness);
   