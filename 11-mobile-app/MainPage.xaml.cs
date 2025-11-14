using _11_mobile_app.ViewModels;
using _11_mobile_app.Models;

namespace _11_mobile_app
{
    public partial class MainPage : ContentPage
    {
        private BboViewModel? ViewModel => BindingContext as BboViewModel;

        public MainPage()
        {
            InitializeComponent();
        }

        private void OnSymbolTapped(object sender, EventArgs e)
        {
            if (sender is Button button && button.BindingContext is BboUpdate bbo)
            {
                if (ViewModel != null)
                {
                    ViewModel.SelectedSymbol = bbo;
                }
            }
        }
    }
}
